// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart';
import 'package:kernel/class_hierarchy.dart'
    show ClassHierarchy, ClassHierarchySubtypes, ClosedWorldClassHierarchy;
import 'package:kernel/core_types.dart';
import 'package:kernel/library_index.dart';
import 'package:kernel/src/printer.dart';
import 'package:kernel/type_environment.dart';
import 'package:vm/metadata/direct_call.dart';
import 'package:vm/metadata/inferred_type.dart';
import 'package:vm/metadata/unboxing_info.dart';
import 'package:wasm_builder/wasm_builder.dart' as w;

import 'class_info.dart';
import 'closures.dart';
import 'code_generator.dart';
import 'constants.dart';
import 'dispatch_table.dart';
import 'dynamic_forwarders.dart';
import 'functions.dart';
import 'globals.dart';
import 'kernel_nodes.dart';
import 'param_info.dart';
import 'records.dart';
import 'reference_extensions.dart';
import 'types.dart';

/// Options controlling the translation.
class TranslatorOptions {
  bool enableAsserts = false;
  bool exportAll = false;
  bool importSharedMemory = false;
  bool inlining = true;
  bool jsCompatibility = false;
  bool omitImplicitTypeChecks = false;
  bool omitExplicitTypeChecks = false;
  bool omitBoundsChecks = false;
  bool polymorphicSpecialization = false;
  bool printKernel = false;
  bool printWasm = false;
  bool minify = false;
  bool verifyTypeChecks = false;
  bool verbose = false;
  bool enableExperimentalFfi = false;
  bool enableExperimentalWasmInterop = false;
  int inliningLimit = 0;
  int? sharedMemoryMaxPages;
  List<int> watchPoints = [];
}

/// The main entry point for the translation from kernel to Wasm and the hub for
/// all global state in the compiler.
///
/// This class also contains utility methods for types and code generation used
/// throughout the compiler.
class Translator with KernelNodes {
  // Options for the translation.
  final TranslatorOptions options;

  // Kernel input and context.
  @override
  final Component component;
  final List<Library> libraries;
  final CoreTypes coreTypes;
  late final TypeEnvironment typeEnvironment;
  final ClosedWorldClassHierarchy hierarchy;
  late final ClassHierarchySubtypes subtypes;

  // TFA-inferred metadata.
  late final Map<TreeNode, DirectCallMetadata> directCallMetadata =
      (component.metadata[DirectCallMetadataRepository.repositoryTag]
              as DirectCallMetadataRepository)
          .mapping;
  late final Map<TreeNode, InferredType> inferredTypeMetadata =
      (component.metadata[InferredTypeMetadataRepository.repositoryTag]
              as InferredTypeMetadataRepository)
          .mapping;
  late final Map<TreeNode, InferredType> inferredArgTypeMetadata =
      (component.metadata[InferredArgTypeMetadataRepository.repositoryTag]
              as InferredArgTypeMetadataRepository)
          .mapping;
  late final Map<TreeNode, InferredType> inferredReturnTypeMetadata =
      (component.metadata[InferredReturnTypeMetadataRepository.repositoryTag]
              as InferredReturnTypeMetadataRepository)
          .mapping;
  late final Map<TreeNode, UnboxingInfoMetadata> unboxingInfoMetadata =
      (component.metadata[UnboxingInfoMetadataRepository.repositoryTag]
              as UnboxingInfoMetadataRepository)
          .mapping;

  // Other parts of the global compiler state.
  @override
  final LibraryIndex index;
  late final ClosureLayouter closureLayouter;
  late final ClassInfoCollector classInfoCollector;
  late final DispatchTable dispatchTable;
  late final Globals globals;
  late final Constants constants;
  late final Types types;
  late final FunctionCollector functions;
  late final DynamicForwarders dynamicForwarders;

  // Information about the program used and updated by the various phases.

  /// [ClassInfo]s of classes in the compilation unit and the [ClassInfo] for
  /// the `#Top` struct. Indexed by class ID. Entries added by
  /// [ClassInfoCollector].
  late final List<ClassInfo> classes;

  /// Same as [classes] but ordered such that info for class at index I
  /// will have class info for superlass/superinterface at <I).
  late final List<ClassInfo> classesSupersFirst;

  late final ClassIdNumbering classIdNumbering;

  /// [ClassInfo]s of classes in the compilation unit. Entries added by
  /// [ClassInfoCollector].
  final Map<Class, ClassInfo> classInfo = {};

  /// Internalized strings to move to the JS runtime
  final List<String> internalizedStringsForJSRuntime = [];
  final Map<String, w.Global> _internalizedStringGlobals = {};

  final Map<w.HeapType, ClassInfo> classForHeapType = {};
  final Map<Field, int> fieldIndex = {};
  final Map<TypeParameter, int> typeParameterIndex = {};
  final Map<Reference, ParameterInfo> staticParamInfo = {};
  final Map<Field, w.Table> declaredTables = {};
  final Set<Member> membersContainingInnerFunctions = {};
  final Set<Member> membersBeingGenerated = {};
  final Map<Reference, Closures> constructorClosures = {};
  final List<_FunctionGenerator> _pendingFunctions = [];
  late final Procedure mainFunction;
  late final w.ModuleBuilder m;
  late final w.FunctionBuilder initFunction;
  late final w.ValueType voidMarker;
  // Lazily create exception tag if used.
  late final w.Tag exceptionTag = createExceptionTag();
  // Lazily import FFI memory if used.
  late final w.Memory ffiMemory = m.memories.import("ffi", "memory",
      options.importSharedMemory, 0, options.sharedMemoryMaxPages);

  /// Maps record shapes to the record class for the shape. Classes generated
  /// by `record_class_generator` library.
  final Map<RecordShape, Class> recordClasses;

  // Caches for when identical source constructs need a common representation.
  final Map<w.StorageType, w.ArrayType> immutableArrayTypeCache = {};
  final Map<w.StorageType, w.ArrayType> mutableArrayTypeCache = {};
  final Map<w.BaseFunction, w.Global> functionRefCache = {};
  final Map<Procedure, ClosureImplementation> tearOffFunctionCache = {};

  // Some convenience accessors for commonly used values.
  late final ClassInfo topInfo = classes[0];
  late final ClassInfo objectInfo = classInfo[coreTypes.objectClass]!;
  late final ClassInfo closureInfo = classInfo[closureClass]!;
  late final ClassInfo stackTraceInfo = classInfo[stackTraceClass]!;
  late final ClassInfo recordInfo = classInfo[coreTypes.recordClass]!;
  late final w.ArrayType typeArrayType =
      arrayTypeForDartType(InterfaceType(typeClass, Nullability.nonNullable));
  late final w.ArrayType listArrayType = (classInfo[listBaseClass]!
          .struct
          .fields[FieldIndex.listArray]
          .type as w.RefType)
      .heapType as w.ArrayType;
  late final w.ArrayType nullableObjectArrayType =
      arrayTypeForDartType(coreTypes.objectRawType(Nullability.nullable));
  late final w.RefType typeArrayTypeRef =
      w.RefType.def(typeArrayType, nullable: false);
  late final w.RefType nullableObjectArrayTypeRef =
      w.RefType.def(nullableObjectArrayType, nullable: false);

  late final PartialInstantiator partialInstantiator =
      PartialInstantiator(this);

  /// Dart types that have specialized Wasm representations.
  late final Map<Class, w.StorageType> builtinTypes = {
    coreTypes.boolClass: w.NumType.i32,
    coreTypes.intClass: w.NumType.i64,
    coreTypes.doubleClass: w.NumType.f64,
    boxedBoolClass: w.NumType.i32,
    boxedIntClass: w.NumType.i64,
    boxedDoubleClass: w.NumType.f64,
    ffiPointerClass: w.NumType.i32,
    wasmI8Class: w.PackedType.i8,
    wasmI16Class: w.PackedType.i16,
    wasmI32Class: w.NumType.i32,
    wasmI64Class: w.NumType.i64,
    wasmF32Class: w.NumType.f32,
    wasmF64Class: w.NumType.f64,
    wasmAnyRefClass: const w.RefType.any(nullable: false),
    wasmExternRefClass: const w.RefType.extern(nullable: false),
    wasmFuncRefClass: const w.RefType.func(nullable: false),
    wasmEqRefClass: const w.RefType.eq(nullable: false),
    wasmStructRefClass: const w.RefType.struct(nullable: false),
    wasmArrayRefClass: const w.RefType.array(nullable: false),
  };

  /// The box classes corresponding to each of the value types.
  late final Map<w.ValueType, Class> boxedClasses = {
    w.NumType.i32: boxedBoolClass,
    w.NumType.i64: boxedIntClass,
    w.NumType.f64: boxedDoubleClass,
  };

  /// Classes whose identity hash code is their hash code rather than the
  /// identity hash code field in the struct. Each implementation class maps to
  /// the class containing the implementation of its `hashCode` getter.
  late final Map<Class, Class> valueClasses = {
    boxedIntClass: boxedIntClass,
    boxedDoubleClass: boxedDoubleClass,
    boxedBoolClass: coreTypes.boolClass,
    if (!options.jsCompatibility) ...{
      oneByteStringClass: stringBaseClass,
      twoByteStringClass: stringBaseClass
    },
    if (options.jsCompatibility) ...{jsStringClass: jsStringClass},
  };

  /// Type for vtable entries for dynamic calls. These entries are used in
  /// dynamic invocations and `Function.apply`.
  late final w.FunctionType dynamicCallVtableEntryFunctionType =
      m.types.defineFunction([
    // Closure
    w.RefType.def(closureLayouter.closureBaseStruct, nullable: false),

    // Type arguments
    typeArrayTypeRef,

    // Positional arguments
    nullableObjectArrayTypeRef,

    // Named arguments, represented as array of symbol and object pairs
    nullableObjectArrayTypeRef,
  ], [
    topInfo.nullableType
  ]);

  /// Type of a dynamic invocation forwarder function.
  late final w.FunctionType dynamicInvocationForwarderFunctionType =
      m.types.defineFunction([
    // Receiver
    topInfo.nonNullableType,

    // Type arguments
    typeArrayTypeRef,

    // Positional arguments
    nullableObjectArrayTypeRef,

    // Named arguments, represented as array of symbol and object pairs
    nullableObjectArrayTypeRef,
  ], [
    topInfo.nullableType
  ]);

  /// Type of a dynamic get forwarder function.
  late final w.FunctionType dynamicGetForwarderFunctionType =
      m.types.defineFunction([
    // Receiver
    topInfo.nonNullableType,
  ], [
    topInfo.nullableType
  ]);

  /// Type of a dynamic set forwarder function.
  late final w.FunctionType dynamicSetForwarderFunctionType =
      m.types.defineFunction([
    // Receiver
    topInfo.nonNullableType,

    // Positional argument
    topInfo.nullableType,
  ], [
    topInfo.nullableType
  ]);

  Translator(this.component, this.coreTypes, this.index, this.recordClasses,
      this.options)
      : libraries = component.libraries,
        hierarchy =
            ClassHierarchy(component, coreTypes) as ClosedWorldClassHierarchy {
    typeEnvironment = TypeEnvironment(coreTypes, hierarchy);
    subtypes = hierarchy.computeSubtypesInformation();
    closureLayouter = ClosureLayouter(this);
    classInfoCollector = ClassInfoCollector(this);
    dispatchTable = DispatchTable(this);
    functions = FunctionCollector(this);
    types = Types(this);
    dynamicForwarders = DynamicForwarders(this);
  }

  w.Module translate() {
    m = w.ModuleBuilder(watchPoints: options.watchPoints);
    voidMarker = w.RefType.def(w.StructType("void"), nullable: true);
    mainFunction = component.mainMethod!;

    // Collect imports and exports as the very first thing so the function types
    // for the imports can be places in singleton recursion groups.
    functions.collectImportsAndExports();

    closureLayouter.collect([mainFunction.function]);
    classInfoCollector.collect();

    initFunction =
        m.functions.define(m.types.defineFunction(const [], const []), "#init");
    m.functions.start = initFunction;

    globals = Globals(this);
    constants = Constants(this);

    dispatchTable.build();

    m.exports.export("\$getMain", generateGetMain(mainFunction));

    functions.initialize();
    while (!functions.isWorkListEmpty()) {
      Reference reference = functions.popWorkList();
      Member member = reference.asMember;
      var function = functions.getExistingFunction(reference) as w.BaseFunction;

      String canonicalName = "$member";
      if (reference.isSetter) {
        canonicalName = "$canonicalName=";
      } else if (reference.isGetter || reference.isTearOffReference) {
        int dot = canonicalName.indexOf('.');
        canonicalName =
            '${canonicalName.substring(0, dot + 1)}=${canonicalName.substring(dot + 1)}';
      }
      canonicalName = member.enclosingLibrary == libraries.first
          ? canonicalName
          : "${member.enclosingLibrary.importUri} $canonicalName";

      String? exportName = functions.getExport(reference);

      if (options.printKernel || options.printWasm) {
        String header = "#${function.name}: $canonicalName";
        if (exportName != null) {
          header = "$header (exported as $exportName)";
        }
        if (reference.isTypeCheckerReference) {
          header = "$header (type checker)";
        }
        print(header);
        print(member.function
            ?.computeFunctionType(Nullability.nonNullable)
            .toStringInternal());
      }
      if (options.printKernel && !reference.isTypeCheckerReference) {
        if (member is Constructor) {
          Class cls = member.enclosingClass;
          for (Field field in cls.fields) {
            if (field.isInstanceMember && field.initializer != null) {
              print("${field.name}: ${field.initializer}");
            }
          }
          for (Initializer initializer in member.initializers) {
            print(initializer);
          }
        }
        Statement? body = member.function?.body;
        if (body != null) {
          print(body);
        }
        if (!options.printWasm) print("");
      }

      if (options.exportAll && exportName == null) {
        m.exports.export(canonicalName, function);
      }

      final CodeGenerator codeGen = CodeGenerator.forFunction(
          this, member.function, function as w.FunctionBuilder, reference);
      codeGen.generate();

      if (options.printWasm) {
        print(codeGen.function.type);
        print(codeGen.function.body.trace);
      }

      // The constructor allocator, initializer, and body functions all
      // share the same Closures, which will contain all the lambdas in the
      // constructor initializer and body. But, we only want to generate
      // the lambda functions once, so we only generate lambdas when the
      // constructor initializer methods are generated.
      if (member is! Constructor || reference.isInitializerReference) {
        for (Lambda lambda in codeGen.closures.lambdas.values) {
          w.BaseFunction lambdaFunction = CodeGenerator.forFunction(
                  this, lambda.functionNode, lambda.function, reference)
              .generateLambda(lambda, codeGen.closures);
          _printFunction(lambdaFunction, "$canonicalName (closure)");
        }
      }

      // Use an indexed loop to handle pending closure trampolines, since new
      // entries might be added during iteration.
      for (int i = 0; i < _pendingFunctions.length; i++) {
        _pendingFunctions[i].generate(this);
      }
      _pendingFunctions.clear();
    }

    constructorClosures.clear();
    dispatchTable.output();
    initFunction.body.end();

    for (ConstantInfo info in constants.constantInfo.values) {
      w.BaseFunction? function = info.function;
      if (function != null) {
        _printFunction(function, info.constant);
      } else {
        if (options.printWasm) {
          print("Global #${info.global.name}: ${info.constant}");
          final global = info.global;
          if (global is w.GlobalBuilder) {
            print(global.initializer.trace);
          }
        }
      }
    }
    _printFunction(initFunction, "init");

    return m.build();
  }

  void _printFunction(w.BaseFunction function, Object name) {
    if (options.printWasm) {
      print("#${function.name}: $name");
      final f = function;
      if (f is w.FunctionBuilder) {
        print(f.body.trace);
      }
    }
  }

  w.BaseFunction generateGetMain(Procedure mainFunction) {
    final getMain = m.functions.define(m.types
        .defineFunction(const [], const [w.RefType.any(nullable: true)]));
    constants.instantiateConstant(getMain, getMain.body,
        StaticTearOffConstant(mainFunction), getMain.type.outputs.single);
    getMain.body.end();

    return getMain;
  }

  Class classForType(DartType type) {
    return type is InterfaceType
        ? type.classNode
        : type is TypeParameterType
            ? classForType(type.bound)
            : coreTypes.objectClass;
  }

  /// Compute the runtime type of a tear-off. This is the signature of the
  /// method with the types of all covariant parameters replaced by `Object?`.
  FunctionType getTearOffType(Procedure method) {
    assert(method.kind == ProcedureKind.Method);
    final FunctionType staticType = method.getterType as FunctionType;

    final positionalParameters = List.of(staticType.positionalParameters);
    assert(positionalParameters.length ==
        method.function.positionalParameters.length);

    final namedParameters = List.of(staticType.namedParameters);
    assert(namedParameters.length == method.function.namedParameters.length);

    if (!options.omitImplicitTypeChecks) {
      for (int i = 0; i < positionalParameters.length; i++) {
        final param = method.function.positionalParameters[i];
        if (param.isCovariantByDeclaration || param.isCovariantByClass) {
          positionalParameters[i] = coreTypes.objectNullableRawType;
        }
      }

      for (int i = 0; i < namedParameters.length; i++) {
        final param = method.function.namedParameters[i];
        if (param.isCovariantByDeclaration || param.isCovariantByClass) {
          namedParameters[i] = NamedType(
              namedParameters[i].name, coreTypes.objectNullableRawType,
              isRequired: namedParameters[i].isRequired);
        }
      }
    }

    return FunctionType(
        positionalParameters, staticType.returnType, Nullability.nonNullable,
        namedParameters: namedParameters,
        typeParameters: staticType.typeParameters,
        requiredParameterCount: staticType.requiredParameterCount);
  }

  /// Creates a [Tag] for a void [FunctionType] with two parameters,
  /// a [topInfo.nonNullableType] parameter to hold an exception, and a
  /// [stackTraceInfo.nonNullableType] to hold a stack trace. This single
  /// exception tag is used to throw and catch all Dart exceptions.
  w.Tag createExceptionTag() {
    w.FunctionType tagType = m.types.defineFunction(
        [topInfo.nonNullableType, stackTraceInfo.repr.nonNullableType],
        const []);
    w.Tag tag = m.tags.define(tagType);
    return tag;
  }

  w.ValueType translateType(DartType type) {
    w.StorageType wasmType = translateStorageType(type);
    if (wasmType is w.ValueType) return wasmType;

    // We represent the packed i8/i16 types as zero-extended i32 type.
    // Dart code can currently only obtain them via loading from packed arrays
    // and only use them for storing into packed arrays (there are no
    // conversion or other operations on WasmI8/WasmI16).
    if (wasmType is w.PackedType) return w.NumType.i32;
    throw "Cannot translate $type to wasm type.";
  }

  bool _hasSuperclass(Class cls, Class superclass) {
    while (cls.superclass != null) {
      cls = cls.superclass!;
      if (cls == superclass) return true;
    }
    return false;
  }

  bool isWasmType(Class cls) =>
      cls == wasmTypesBaseClass || _hasSuperclass(cls, wasmTypesBaseClass);

  w.StorageType translateStorageType(DartType type) {
    bool nullable = type.isPotentiallyNullable;
    if (type is InterfaceType) {
      Class cls = type.classNode;

      // Abstract `Function`?
      if (cls == coreTypes.functionClass) {
        return w.RefType.def(closureLayouter.closureBaseStruct,
            nullable: nullable);
      }

      // Wasm array?
      if (cls.superclass == wasmArrayRefClass) {
        DartType elementType = type.typeArguments.single;
        return w.RefType.def(arrayTypeForDartType(elementType),
            nullable: nullable);
      }

      // Wasm function?
      if (cls == wasmFunctionClass) {
        DartType functionType = type.typeArguments.single;
        if (functionType is! FunctionType) {
          throw "The type argument of a WasmFunction must be a function type";
        }
        if (functionType.typeParameters.isNotEmpty ||
            functionType.namedParameters.isNotEmpty ||
            functionType.requiredParameterCount !=
                functionType.positionalParameters.length) {
          throw "A WasmFunction can't have optional/type parameters";
        }
        DartType returnType = functionType.returnType;
        bool voidReturn = returnType is InterfaceType &&
            returnType.classNode == wasmVoidClass;
        List<w.ValueType> inputs = [
          for (DartType type in functionType.positionalParameters)
            translateType(type)
        ];
        List<w.ValueType> outputs = [
          if (!voidReturn) translateType(functionType.returnType)
        ];
        w.FunctionType wasmType = m.types.defineFunction(inputs, outputs);
        return w.RefType.def(wasmType, nullable: nullable);
      }

      // Other built-in type?
      w.StorageType? builtin = builtinTypes[cls];
      if (builtin != null) {
        if (!nullable) {
          return builtin;
        }
        if (isWasmType(cls)) {
          if (builtin.isPrimitive) throw "Wasm numeric types can't be nullable";
          return (builtin as w.RefType).withNullability(nullable);
        }
        final boxedBuiltin = classInfo[boxedClasses[builtin]!]!;
        return nullable
            ? boxedBuiltin.nullableType
            : boxedBuiltin.nonNullableType;
      }

      // Regular class.
      return classInfo[cls]!.repr.typeWithNullability(nullable);
    }
    if (type is DynamicType || type is VoidType) {
      return topInfo.nullableType;
    }
    if (type is NullType || type is NeverType) {
      return const w.RefType.none(nullable: true);
    }
    if (type is TypeParameterType) {
      return translateStorageType(nullable
          ? type.bound.withDeclaredNullability(Nullability.nullable)
          : type.bound);
    }
    if (type is IntersectionType) {
      return translateStorageType(type.left);
    }
    if (type is FutureOrType) {
      return topInfo.typeWithNullability(nullable);
    }
    if (type is FunctionType) {
      ClosureRepresentation? representation =
          closureLayouter.getClosureRepresentation(
              type.typeParameters.length,
              type.positionalParameters.length,
              type.namedParameters.map((p) => p.name).toList());
      return w.RefType.def(
          representation != null
              ? representation.closureStruct
              : classInfo[typeClass]!.struct,
          nullable: nullable);
    }
    if (type is ExtensionType) {
      return translateStorageType(type.extensionTypeErasure);
    }
    if (type is RecordType) {
      return getRecordClassInfo(type).typeWithNullability(nullable);
    }
    throw "Unsupported type ${type.runtimeType}";
  }

  w.ArrayType arrayTypeForDartType(DartType type) {
    while (type is TypeParameterType) {
      type = type.bound;
    }
    return wasmArrayType(
        translateStorageType(type), type.toText(defaultAstTextStrategy));
  }

  w.ArrayType wasmArrayType(w.StorageType type, String name,
      {bool mutable = true}) {
    final cache = mutable ? mutableArrayTypeCache : immutableArrayTypeCache;
    return cache.putIfAbsent(
        type,
        () => m.types.defineArray("Array<$name>",
            elementType: w.FieldType(type, mutable: mutable)));
  }

  /// Translate a Dart type as it should appear on parameters and returns of
  /// imported and exported functions. All wasm types are allowed on the interop
  /// boundary, but in order to be compatible with the `--closed-world` mode of
  /// Binaryen, we coerce all reference types to abstract reference types
  /// (`anyref`, `funcref` or `externref`).
  /// This function can be called before the class info is built.
  w.ValueType translateExternalType(DartType type) {
    bool isPotentiallyNullable = type.isPotentiallyNullable;
    if (type is InterfaceType) {
      Class cls = type.classNode;
      if (cls == wasmFuncRefClass || cls == wasmFunctionClass) {
        return w.RefType.func(nullable: isPotentiallyNullable);
      }
      if (cls == wasmExternRefClass) {
        return w.RefType.extern(nullable: isPotentiallyNullable);
      }
      if (!isPotentiallyNullable) {
        w.StorageType? builtin = builtinTypes[cls];
        if (builtin != null && builtin.isPrimitive) {
          return builtin as w.ValueType;
        }
      }
    }
    // TODO(joshualitt): We'd like to use the potential nullability here too,
    // but unfortunately this seems to break things.
    return w.RefType.any(nullable: true);
  }

  w.Global makeFunctionRef(w.BaseFunction f) {
    return functionRefCache.putIfAbsent(f, () {
      final global = m.globals.define(
          w.GlobalType(w.RefType.def(f.type, nullable: false), mutable: false));
      global.initializer.ref_func(f);
      global.initializer.end();
      return global;
    });
  }

  ClosureImplementation getTearOffClosure(Procedure member) {
    return tearOffFunctionCache.putIfAbsent(member, () {
      assert(member.kind == ProcedureKind.Method);
      w.BaseFunction target = functions.getFunction(member.reference);
      return getClosure(member.function, target, paramInfoFor(member.reference),
          "$member tear-off");
    });
  }

  ClosureImplementation getClosure(FunctionNode functionNode,
      w.BaseFunction target, ParameterInfo paramInfo, String name) {
    // The target function takes an extra initial parameter if it's a function
    // expression / local function (which takes a context) or a tear-off of an
    // instance method (which takes a receiver).
    bool takesContextOrReceiver =
        paramInfo.member == null || paramInfo.member!.isInstanceMember;

    // Look up the closure representation for the signature.
    int typeCount = functionNode.typeParameters.length;
    int positionalCount = functionNode.positionalParameters.length;
    final List<VariableDeclaration> namedParamsSorted =
        functionNode.namedParameters.toList()
          ..sort((p1, p2) => p1.name!.compareTo(p2.name!));
    List<String> names = namedParamsSorted.map((p) => p.name!).toList();
    assert(typeCount == paramInfo.typeParamCount);
    assert(positionalCount <= paramInfo.positional.length);
    assert(names.length <= paramInfo.named.length);
    assert(target.type.inputs.length ==
        (takesContextOrReceiver ? 1 : 0) +
            paramInfo.typeParamCount +
            paramInfo.positional.length +
            paramInfo.named.length);
    ClosureRepresentation representation = closureLayouter
        .getClosureRepresentation(typeCount, positionalCount, names)!;
    assert(representation.vtableStruct.fields.length ==
        representation.vtableBaseIndex +
            (1 + positionalCount) +
            representation.nameCombinations.length);

    List<w.BaseFunction> functions = [];

    bool canBeCalledWith(int posArgCount, List<String> argNames) {
      if (posArgCount < functionNode.requiredParameterCount) {
        return false;
      }

      int namedArgIdx = 0, namedParamIdx = 0;
      while (namedArgIdx < argNames.length &&
          namedParamIdx < namedParamsSorted.length) {
        int comp = argNames[namedArgIdx]
            .compareTo(namedParamsSorted[namedParamIdx].name!);
        if (comp < 0) {
          // Unexpected named argument passed
          return false;
        } else if (comp > 0) {
          if (namedParamsSorted[namedParamIdx].isRequired) {
            // Required named parameter not passed
            return false;
          } else {
            // Optional named parameter not passed
            namedParamIdx++;
            continue;
          }
        } else {
          // Expected required or optional named parameter passed
          namedArgIdx++;
          namedParamIdx++;
        }
      }

      if (namedArgIdx < argNames.length) {
        // Unexpected named argument(s) passed
        return false;
      }

      while (namedParamIdx < namedParamsSorted.length) {
        if (namedParamsSorted[namedParamIdx++].isRequired) {
          // Required named parameter not passed
          return false;
        }
      }

      return true;
    }

    w.BaseFunction makeTrampoline(
        w.FunctionType signature, int posArgCount, List<String> argNames) {
      final trampoline = m.functions.define(signature, "$name trampoline");

      // Defer generation of the trampoline body to avoid cyclic dependency
      // when a tear-off constant is used as default value in the torn-off
      // function.
      _pendingFunctions.add(_ClosureTrampolineGenerator(trampoline, target,
          typeCount, posArgCount, argNames, paramInfo, takesContextOrReceiver));

      return trampoline;
    }

    w.BaseFunction makeDynamicCallEntry() {
      final function = m.functions.define(
          dynamicCallVtableEntryFunctionType, "$name dynamic call entry");

      // Defer generation of the trampoline body to avoid cyclic dependency
      // when a tear-off constant is used as default value in the torn-off
      // function.
      _pendingFunctions.add(_ClosureDynamicEntryGenerator(
          functionNode, target, paramInfo, name, function));

      return function;
    }

    void fillVtableEntry(
        w.InstructionsBuilder ib, int posArgCount, List<String> argNames) {
      int fieldIndex = representation.vtableBaseIndex + functions.length;
      assert(fieldIndex ==
          representation.fieldIndexForSignature(posArgCount, argNames));
      w.FunctionType signature = representation.getVtableFieldType(fieldIndex);
      w.BaseFunction function = canBeCalledWith(posArgCount, argNames)
          ? makeTrampoline(signature, posArgCount, argNames)
          : globals.getDummyFunction(signature);
      functions.add(function);
      ib.ref_func(function);
    }

    final vtable = m.globals.define(w.GlobalType(
        w.RefType.def(representation.vtableStruct, nullable: false),
        mutable: false));
    final ib = vtable.initializer;
    final dynamicCallEntry = makeDynamicCallEntry();
    ib.ref_func(dynamicCallEntry);
    if (representation.isGeneric) {
      ib.ref_func(representation.instantiationTypeComparisonFunction);
      ib.ref_func(representation.instantiationTypeHashFunction);
      ib.ref_func(representation.instantiationFunction);
    }
    for (int posArgCount = 0; posArgCount <= positionalCount; posArgCount++) {
      fillVtableEntry(ib, posArgCount, const []);
    }
    for (NameCombination nameCombination in representation.nameCombinations) {
      fillVtableEntry(ib, positionalCount, nameCombination.names);
    }
    ib.struct_new(representation.vtableStruct);
    ib.end();

    return ClosureImplementation(
        representation, functions, dynamicCallEntry, vtable);
  }

  w.ValueType outputOrVoid(List<w.ValueType> outputs) {
    return outputs.isEmpty ? voidMarker : outputs.single;
  }

  bool needsConversion(w.ValueType from, w.ValueType to) {
    return (from == voidMarker) ^ (to == voidMarker) || !from.isSubtypeOf(to);
  }

  void convertType(
      w.FunctionBuilder function, w.ValueType from, w.ValueType to) {
    final b = function.body;
    if (from == voidMarker || to == voidMarker) {
      if (from != voidMarker) {
        b.drop();
        return;
      }
      if (to != voidMarker) {
        // This can happen e.g. when a `return;` is guaranteed to be never taken
        // but TFA didn't remove the dead code. In that case we synthesize a
        // dummy value.
        globals.instantiateDummyValue(b, to);
        return;
      }
    }

    if (!from.isSubtypeOf(to)) {
      if (from is w.RefType && to is w.RefType) {
        if (from.withNullability(false).isSubtypeOf(to)) {
          // Null check
          b.ref_as_non_null();
        } else {
          // Downcast
          b.ref_cast(to);
        }
      } else if (to is w.RefType) {
        // Boxing
        ClassInfo info = classInfo[boxedClasses[from]!]!;
        assert(info.struct.isSubtypeOf(to.heapType));
        w.Local temp = function.addLocal(from);
        b.local_set(temp);
        b.i32_const(info.classId);
        b.local_get(temp);
        b.struct_new(info.struct);
      } else if (from is w.RefType) {
        // Unboxing
        ClassInfo info = classInfo[boxedClasses[to]!]!;
        if (!from.heapType.isSubtypeOf(info.struct)) {
          // Cast to box type
          b.ref_cast(info.nonNullableType);
        }
        b.struct_get(info.struct, FieldIndex.boxValue);
      } else {
        throw "Conversion between non-reference types";
      }
    }
  }

  w.FunctionType signatureFor(Reference target) {
    Member member = target.asMember;
    if (member.isInstanceMember) {
      return dispatchTable.selectorForTarget(target).signature;
    } else {
      return functions.getFunctionType(target);
    }
  }

  ParameterInfo paramInfoFor(Reference target) {
    Member member = target.asMember;
    if (member.isInstanceMember) {
      return dispatchTable.selectorForTarget(target).paramInfo;
    } else {
      return staticParamInfo.putIfAbsent(
          target, () => ParameterInfo.fromMember(target));
    }
  }

  w.ValueType preciseThisFor(Member member, {bool nullable = false}) {
    assert(member.isInstanceMember || member is Constructor);

    Class cls = member.enclosingClass!;
    final w.StorageType? builtin = builtinTypes[cls];
    final boxClass = boxedClasses[builtin];
    if (boxClass != null) {
      // We represent `this` as an unboxed type.
      if (!nullable) return builtin as w.ValueType;
      // Otherwise we use [boxClass] to represent `this`.
      cls = boxClass;
    }
    final representationClassInfo = classInfo[cls]!.repr;
    return nullable
        ? representationClassInfo.nullableType
        : representationClassInfo.nonNullableType;
  }

  /// Get the Wasm table declared by [field], or `null` if [field] is not a
  /// declaration of a Wasm table.
  ///
  /// This function participates in tree shaking in the sense that if it's
  /// never called for a particular table declaration, that table is not added
  /// to the output module.
  w.Table? getTable(Field field) {
    w.Table? table = declaredTables[field];
    if (table != null) return table;
    DartType fieldType = field.type;
    if (fieldType is InterfaceType && fieldType.classNode == wasmTableClass) {
      w.RefType elementType =
          translateType(fieldType.typeArguments.single) as w.RefType;
      Expression sizeExp = (field.initializer as ConstructorInvocation)
          .arguments
          .positional
          .single;
      if (sizeExp is StaticGet && sizeExp.target is Field) {
        sizeExp = (sizeExp.target as Field).initializer!;
      }
      int size = sizeExp is ConstantExpression
          ? (sizeExp.constant as IntConstant).value
          : (sizeExp as IntLiteral).value;
      return declaredTables[field] = m.tables.define(elementType, size);
    }
    return null;
  }

  Member? singleTarget(TreeNode node) {
    return directCallMetadata[node]?.targetMember;
  }

  DartType typeOfParameterVariable(VariableDeclaration node, bool isRequired) {
    // We have a guarantee that inferred types are correct.
    final inferredType = _inferredTypeOfParameterVariable(node);
    if (inferredType != null) {
      return isRequired
          ? inferredType
          : inferredType.withDeclaredNullability(Nullability.nullable);
    }

    final isCovariant =
        node.isCovariantByDeclaration || node.isCovariantByClass;
    if (isCovariant) {
      // The type argument of a static type is not required to conform
      // to the bounds of the type variable. Thus, any object can be
      // passed to a parameter that is covariant by class.
      return coreTypes.objectNullableRawType;
    }

    return node.type;
  }

  DartType typeOfReturnValue(Member member) {
    if (member is Field) return typeOfField(member);

    return _inferredTypeOfReturnValue(member) ?? member.function!.returnType;
  }

  DartType typeOfField(Field node) {
    assert(!node.isLate);
    return _inferredTypeOfField(node) ?? node.type;
  }

  w.ValueType translateTypeOfParameter(
      VariableDeclaration node, bool isRequired) {
    return translateType(typeOfParameterVariable(node, isRequired));
  }

  w.ValueType translateTypeOfReturnValue(Member node) {
    return translateType(typeOfReturnValue(node));
  }

  w.ValueType translateTypeOfField(Field node) {
    return translateType(typeOfField(node));
  }

  w.ValueType translateTypeOfLocalVariable(VariableDeclaration node) {
    return translateType(_inferredTypeOfLocalVariable(node) ?? node.type);
  }

  DartType? _inferredTypeOfParameterVariable(VariableDeclaration node) {
    return _filterInferredType(node.type, inferredArgTypeMetadata[node]);
  }

  DartType? _inferredTypeOfReturnValue(Member node) {
    return _filterInferredType(
        node.function!.returnType, inferredReturnTypeMetadata[node]);
  }

  DartType? _inferredTypeOfField(Field node) {
    return _filterInferredType(node.type, inferredTypeMetadata[node]);
  }

  DartType? _inferredTypeOfLocalVariable(VariableDeclaration node) {
    InferredType? inferredType = inferredTypeMetadata[node];
    if (node.isFinal) {
      inferredType ??= inferredTypeMetadata[node.initializer];
    }
    return _filterInferredType(node.type, inferredType);
  }

  DartType? _filterInferredType(
      DartType defaultType, InferredType? inferredType) {
    if (inferredType == null) return null;

    // To check whether [inferredType] is more precise than [defaultType] we
    // require it (for now) to be an interface type.
    if (defaultType is! InterfaceType) return null;

    final concreteClass = inferredType.concreteClass;
    if (concreteClass == null) return null;
    // TFA doesn't know how dart2wasm represents closures
    if (concreteClass == closureClass) return null;
    // The WasmFunction<>/WasmArray<>/WasmTable<> types need concrete type
    // arguments.
    if (concreteClass == wasmFunctionClass) return null;
    if (concreteClass == wasmArrayClass) return null;
    if (concreteClass == wasmTableClass) return null;

    // If the TFA inferred class is the same as the [defaultType] we prefer the
    // latter as it has the correct type arguments.
    if (concreteClass == defaultType.classNode) return null;

    // Sometimes we get inferred types that violate soundness (and would result
    // in a runtime error, e.g. in a dynamic invocation forwarder passing an
    // object of incorrect type to a target).
    if (!hierarchy.isSubInterfaceOf(concreteClass, defaultType.classNode)) {
      return null;
    }

    final typeParameters = concreteClass.typeParameters;
    final typeArguments = typeParameters.isEmpty
        ? const <DartType>[]
        : List<DartType>.filled(typeParameters.length, const DynamicType());
    final nullability =
        inferredType.nullable ? Nullability.nullable : Nullability.nonNullable;
    return InterfaceType(concreteClass, nullability, typeArguments);
  }

  bool shouldInline(Reference target) {
    if (!options.inlining) return false;
    Member member = target.asMember;
    if (getPragma<bool>(member, "wasm:never-inline", true) == true) {
      return false;
    }
    if (membersContainingInnerFunctions.contains(member)) return false;
    if (membersBeingGenerated.contains(member)) return false;
    if (target.isInitializerReference) return true;
    if (member is Field) return true;
    if (member.function!.asyncMarker != AsyncMarker.Sync) return false;
    if (getPragma<bool>(member, "wasm:prefer-inline", true) == true) {
      return true;
    }
    Statement? body = member.function!.body;
    return body != null &&
        NodeCounter().countNodes(body) <= options.inliningLimit;
  }

  T? getPragma<T>(Annotatable node, String name, [T? defaultValue]) {
    for (Expression annotation in node.annotations) {
      if (annotation is ConstantExpression) {
        Constant constant = annotation.constant;
        if (constant is InstanceConstant) {
          if (constant.classNode == coreTypes.pragmaClass) {
            Constant? nameConstant =
                constant.fieldValues[coreTypes.pragmaName.fieldReference];
            if (nameConstant is StringConstant && nameConstant.value == name) {
              Constant? value =
                  constant.fieldValues[coreTypes.pragmaOptions.fieldReference];
              if (value == null || value is NullConstant) {
                return defaultValue;
              }
              if (value is PrimitiveConstant<T>) {
                return value.value;
              }
              if (value is! T) {
                throw ArgumentError("$name pragma argument has unexpected type "
                    "${value.runtimeType} (expected $T)");
              }
              return value as T;
            }
          }
        }
      }
    }
    return null;
  }

  w.ValueType makeArray(w.FunctionBuilder function, w.ArrayType arrayType,
      int length, void Function(w.ValueType, int) generateItem) {
    final b = function.body;

    final w.ValueType elementType = arrayType.elementType.type.unpacked;
    final arrayTypeRef = w.RefType.def(arrayType, nullable: false);

    if (length > maxArrayNewFixedLength) {
      // Too long for `array.new_fixed`. Set elements individually.
      b.i32_const(length);
      b.array_new_default(arrayType);
      if (length > 0) {
        final w.Local arrayLocal = function.addLocal(arrayTypeRef);
        b.local_set(arrayLocal);
        for (int i = 0; i < length; i++) {
          b.local_get(arrayLocal);
          b.i32_const(i);
          generateItem(elementType, i);
          b.array_set(arrayType);
        }
        b.local_get(arrayLocal);
      }
    } else {
      for (int i = 0; i < length; i++) {
        generateItem(elementType, i);
      }
      b.array_new_fixed(arrayType, length);
    }
    return arrayTypeRef;
  }

  /// Indexes a Dart `WasmListBase` on the stack.
  void indexList(w.InstructionsBuilder b,
      void Function(w.InstructionsBuilder b) pushIndex) {
    getListBaseArray(b);
    pushIndex(b);
    b.array_get(nullableObjectArrayType);
  }

  /// Pushes a Dart `List`'s length onto the stack as `i32`.
  void getListLength(w.InstructionsBuilder b) {
    ClassInfo info = classInfo[listBaseClass]!;
    b.struct_get(info.struct, FieldIndex.listLength);
    b.i32_wrap_i64();
  }

  /// Get the WasmListBase._data field of type WasmArray<Object?>.
  void getListBaseArray(w.InstructionsBuilder b) {
    ClassInfo info = classInfo[listBaseClass]!;
    b.struct_get(info.struct, FieldIndex.listArray);
  }

  ClassInfo getRecordClassInfo(RecordType recordType) =>
      classInfo[recordClasses[RecordShape.fromType(recordType)]!]!;

  w.Global getInternalizedStringGlobal(String s) {
    w.Global? internalizedString = _internalizedStringGlobals[s];
    if (internalizedString != null) {
      return internalizedString;
    }
    final i = internalizedStringsForJSRuntime.length;
    internalizedString = m.globals.import('s', '$i',
        w.GlobalType(w.RefType.extern(nullable: true), mutable: false));
    _internalizedStringGlobals[s] = internalizedString;
    internalizedStringsForJSRuntime.add(s);
    return internalizedString;
  }
}

abstract class _FunctionGenerator {
  void generate(Translator translator);
}

class _ClosureTrampolineGenerator implements _FunctionGenerator {
  final w.FunctionBuilder trampoline;
  final w.BaseFunction target;
  final int typeCount;
  final int posArgCount;
  final List<String> argNames;
  final ParameterInfo paramInfo;
  final bool takesContextOrReceiver;

  _ClosureTrampolineGenerator(
      this.trampoline,
      this.target,
      this.typeCount,
      this.posArgCount,
      this.argNames,
      this.paramInfo,
      this.takesContextOrReceiver);

  @override
  void generate(Translator translator) {
    final b = trampoline.body;
    int targetIndex = 0;
    if (takesContextOrReceiver) {
      w.Local receiver = trampoline.locals[0];
      b.local_get(receiver);
      translator.convertType(
          trampoline, receiver.type, target.type.inputs[targetIndex++]);
    }
    int argIndex = 1;
    for (int i = 0; i < typeCount; i++) {
      b.local_get(trampoline.locals[argIndex++]);
      targetIndex++;
    }
    for (int i = 0; i < paramInfo.positional.length; i++) {
      if (i < posArgCount) {
        w.Local arg = trampoline.locals[argIndex++];
        b.local_get(arg);
        translator.convertType(
            trampoline, arg.type, target.type.inputs[targetIndex++]);
      } else {
        translator.constants.instantiateConstant(trampoline, b,
            paramInfo.positional[i]!, target.type.inputs[targetIndex++]);
      }
    }
    int argNameIndex = 0;
    for (int i = 0; i < paramInfo.names.length; i++) {
      String argName = paramInfo.names[i];
      if (argNameIndex < argNames.length && argNames[argNameIndex] == argName) {
        w.Local arg = trampoline.locals[argIndex++];
        b.local_get(arg);
        translator.convertType(
            trampoline, arg.type, target.type.inputs[targetIndex++]);
        argNameIndex++;
      } else {
        translator.constants.instantiateConstant(trampoline, b,
            paramInfo.named[argName]!, target.type.inputs[targetIndex++]);
      }
    }
    assert(argIndex == trampoline.type.inputs.length);
    assert(targetIndex == target.type.inputs.length);
    assert(argNameIndex == argNames.length);

    b.call(target);

    translator.convertType(
        trampoline,
        translator.outputOrVoid(target.type.outputs),
        translator.outputOrVoid(trampoline.type.outputs));
    b.end();
  }
}

/// Similar to [_ClosureTrampolineGenerator], but generates dynamic call
/// entries.
class _ClosureDynamicEntryGenerator implements _FunctionGenerator {
  final FunctionNode functionNode;
  final w.BaseFunction target;
  final ParameterInfo paramInfo;
  final String name;
  final w.FunctionBuilder function;

  _ClosureDynamicEntryGenerator(
      this.functionNode, this.target, this.paramInfo, this.name, this.function);

  @override
  void generate(Translator translator) {
    final b = function.body;

    final bool takesContextOrReceiver =
        paramInfo.member == null || paramInfo.member!.isInstanceMember;

    final int typeCount = functionNode.typeParameters.length;

    final closureLocal = function.locals[0];
    final typeArgsListLocal = function.locals[1];
    final posArgsListLocal = function.locals[2];
    final namedArgsListLocal = function.locals[3];

    final positionalRequired =
        paramInfo.positional.where((arg) => arg == null).length;
    final positionalTotal = paramInfo.positional.length;

    // At this point the shape and type checks passed. We have right number
    // of type arguments in the list, but optional positional and named
    // parameters may be missing.

    final targetInputs = target.type.inputs;
    int inputIdx = 0;

    // Push context or receiver
    if (takesContextOrReceiver) {
      final closureBaseType = w.RefType.def(
          translator.closureLayouter.closureBaseStruct,
          nullable: false);
      final closureContextType = w.RefType.struct(nullable: false);

      // Get context, downcast it to expected type
      b.local_get(closureLocal);
      translator.convertType(function, closureLocal.type, closureBaseType);
      b.struct_get(translator.closureLayouter.closureBaseStruct,
          FieldIndex.closureContext);
      translator.convertType(
          function, closureContextType, targetInputs[inputIdx]);
      inputIdx += 1;
    }

    // Push type arguments
    for (int typeIdx = 0; typeIdx < typeCount; typeIdx += 1) {
      b.local_get(typeArgsListLocal);
      b.i32_const(typeIdx);
      b.array_get(translator.typeArrayType);
      translator.convertType(
          function, translator.topInfo.nullableType, targetInputs[inputIdx]);
      inputIdx += 1;
    }

    // Push positional arguments
    for (int posIdx = 0; posIdx < positionalTotal; posIdx += 1) {
      if (posIdx < positionalRequired) {
        // Shape check passed, argument must be passed
        b.local_get(posArgsListLocal);
        b.i32_const(posIdx);
        b.array_get(translator.nullableObjectArrayType);
      } else {
        // Argument may be missing
        b.i32_const(posIdx);
        b.local_get(posArgsListLocal);
        b.array_len();
        b.i32_lt_u();
        b.if_([], [translator.topInfo.nullableType]);
        b.local_get(posArgsListLocal);
        b.i32_const(posIdx);
        b.array_get(translator.nullableObjectArrayType);
        b.else_();
        translator.constants.instantiateConstant(function, b,
            paramInfo.positional[posIdx]!, translator.topInfo.nullableType);
        b.end();
      }
      translator.convertType(
          function, translator.topInfo.nullableType, targetInputs[inputIdx]);
      inputIdx += 1;
    }

    // Push named arguments

    Expression? initializerForNamedParamInMember(String paramName) {
      for (int i = 0; i < functionNode.namedParameters.length; i += 1) {
        if (functionNode.namedParameters[i].name == paramName) {
          return functionNode.namedParameters[i].initializer;
        }
      }
      return null;
    }

    final namedArgValueIndexLocal = function
        .addLocal(translator.classInfo[translator.boxedIntClass]!.nullableType);

    for (String paramName in paramInfo.names) {
      final Constant? paramInfoDefaultValue = paramInfo.named[paramName];
      final Expression? functionNodeDefaultValue =
          initializerForNamedParamInMember(paramName);

      // Get passed value
      b.local_get(namedArgsListLocal);
      translator.constants.instantiateConstant(
          function,
          b,
          SymbolConstant(paramName, null),
          translator.classInfo[translator.symbolClass]!.nonNullableType);
      b.call(translator.functions
          .getFunction(translator.getNamedParameterIndex.reference));
      b.local_set(namedArgValueIndexLocal);

      if (functionNodeDefaultValue == null && paramInfoDefaultValue == null) {
        // Shape check passed, parameter must be passed
        b.local_get(namedArgsListLocal);
        b.local_get(namedArgValueIndexLocal);
        translator.convertType(
            function, namedArgValueIndexLocal.type, w.NumType.i64);
        b.i32_wrap_i64();
        b.array_get(translator.nullableObjectArrayType);
        translator.convertType(
            function,
            translator.nullableObjectArrayType.elementType.type.unpacked,
            target.type.inputs[inputIdx]);
      } else {
        // Parameter may not be passed.
        b.local_get(namedArgValueIndexLocal);
        b.ref_is_null();
        b.if_([], [translator.topInfo.nullableType]);
        if (functionNodeDefaultValue != null) {
          // Used by the member, has a default value
          translator.constants.instantiateConstant(
              function,
              b,
              (functionNodeDefaultValue as ConstantExpression).constant,
              translator.topInfo.nullableType);
        } else {
          // Not used by the member
          translator.constants.instantiateConstant(
            function,
            b,
            paramInfoDefaultValue!,
            translator.topInfo.nullableType,
          );
        }
        b.else_(); // value index not null
        b.local_get(namedArgsListLocal);
        b.local_get(namedArgValueIndexLocal);
        translator.convertType(
            function, namedArgValueIndexLocal.type, w.NumType.i64);
        b.i32_wrap_i64();
        b.array_get(translator.nullableObjectArrayType);
        b.end();
        translator.convertType(
            function, translator.topInfo.nullableType, targetInputs[inputIdx]);
      }
      inputIdx += 1;
    }

    b.call(target);

    translator.convertType(
        function,
        translator.outputOrVoid(target.type.outputs),
        translator.outputOrVoid(function.type.outputs));

    b.end(); // end function
  }
}

class NodeCounter extends VisitorDefault<void> with VisitorVoidMixin {
  int count = 0;

  int countNodes(Node node) {
    count = 0;
    node.accept(this);
    return count;
  }

  @override
  void defaultNode(Node node) {
    count++;
    node.visitChildren(this);
  }
}

/// Creates forwarders for generic functions where the caller passes a constant
/// type argument.
///
/// Let's say we have
///
///     foo<T>(args) => ...;
///
/// and 3 call sites
///
///    foo<int>(args)
///    foo<int>(args)
///    foo<double>(args)
///
/// the callsites can instead call a forwarder
///
///    fooInt(args)
///    fooInt(args)
///    fooDouble(args)
///
///    fooInt(args) => foo<int>(args)
///    fooDouble(args) => foo<double>(args)
///
/// This saves code size on the call site.
class PartialInstantiator {
  final Translator translator;

  final Map<(Reference, DartType), w.BaseFunction> _oneTypeArgument = {};
  final Map<(Reference, DartType, DartType), w.BaseFunction> _twoTypeArguments =
      {};

  PartialInstantiator(this.translator);

  w.BaseFunction getOneTypeArgumentForwarder(
      Reference target, DartType type, String name) {
    assert(translator.types.isTypeConstant(type));

    return _oneTypeArgument.putIfAbsent((target, type), () {
      final wasmTarget = translator.functions.getFunction(target);

      final function = translator.m.functions.define(
          translator.m.types.defineFunction(
            [...wasmTarget.type.inputs.skip(1)],
            wasmTarget.type.outputs,
          ),
          name);
      final b = function.body;
      translator.constants.instantiateConstant(function, b,
          TypeLiteralConstant(type), translator.types.nonNullableTypeType);
      for (int i = 1; i < wasmTarget.type.inputs.length; ++i) {
        b.local_get(b.locals[i - 1]);
      }
      b.call(wasmTarget);
      b.return_();
      b.end();

      return function;
    });
  }

  w.BaseFunction getTwoTypeArgumentForwarder(
      Reference target, DartType type1, DartType type2, String name) {
    assert(translator.types.isTypeConstant(type1));
    assert(translator.types.isTypeConstant(type2));

    return _twoTypeArguments.putIfAbsent((target, type1, type2), () {
      final wasmTarget = translator.functions.getFunction(target);

      final function = translator.m.functions.define(
          translator.m.types.defineFunction(
            [...wasmTarget.type.inputs.skip(2)],
            wasmTarget.type.outputs,
          ),
          name);
      final b = function.body;
      translator.constants.instantiateConstant(function, b,
          TypeLiteralConstant(type1), translator.types.nonNullableTypeType);
      translator.constants.instantiateConstant(function, b,
          TypeLiteralConstant(type2), translator.types.nonNullableTypeType);
      for (int i = 2; i < wasmTarget.type.inputs.length; ++i) {
        b.local_get(b.locals[i - 2]);
      }
      b.call(wasmTarget);
      b.return_();
      b.end();

      return function;
    });
  }
}
