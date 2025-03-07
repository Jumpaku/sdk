// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' as io;
import 'dart:typed_data';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/visitor.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/dart/analysis/results.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/summary2/macro.dart';
import 'package:analyzer/src/summary2/macro_application.dart';
import 'package:analyzer/src/summary2/macro_application_error.dart';
import 'package:analyzer/src/utilities/extensions/file_system.dart';
import 'package:collection/collection.dart';
import 'package:macros/src/bootstrap.dart' as macro;
import 'package:macros/src/executor/serialization.dart' as macro;
import 'package:path/path.dart' as package_path;
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../util/tree_string_sink.dart';
import '../dart/resolution/context_collection_resolution.dart';
import '../dart/resolution/node_text_expectations.dart';
import 'element_text.dart';
import 'elements_base.dart';
import 'macros_environment.dart';

main() {
  try {
    MacrosEnvironment.instance;
  } catch (_) {
    print('Cannot initialize environment. Skip macros tests.');
    test('fake', () {});
    return;
  }

  defineReflectiveSuite(() {
    defineReflectiveTests(MacroArgumentsTest);
    defineReflectiveTests(MacroIncrementalTest);
    defineReflectiveTests(MacroIntrospectNodeTest);
    defineReflectiveTests(MacroIntrospectNodeDefinitionsTest);
    defineReflectiveTests(MacroIntrospectElementTest);
    defineReflectiveTests(MacroTypesTest_keepLinking);
    defineReflectiveTests(MacroTypesTest_fromBytes);
    defineReflectiveTests(MacroDeclarationsTest_keepLinking);
    defineReflectiveTests(MacroDeclarationsTest_fromBytes);
    defineReflectiveTests(MacroDefinitionTest_keepLinking);
    defineReflectiveTests(MacroDefinitionTest_fromBytes);
    defineReflectiveTests(MacroElementsTest_keepLinking);
    defineReflectiveTests(MacroElementsTest_fromBytes);
    defineReflectiveTests(MacroApplicationOrderTest_keepLinking);
    defineReflectiveTests(MacroApplicationOrderTest_fromBytes);
    defineReflectiveTests(MacroCodeGenerationTest);
    defineReflectiveTests(MacroStaticTypeTest);
    defineReflectiveTests(MacroExampleTest);
    defineReflectiveTests(UpdateNodeTextExpectations);
  });
}

abstract class MacroApplicationOrderTest extends MacroElementsBaseTest {
  @override
  Future<void> setUp() async {
    await super.setUp();

    newFile(
      '$testPackageLibPath/order.dart',
      _getMacroCode('order.dart'),
    );
  }

  test_declarations_class_constructorsOf_alreadyDone() async {
    var library = await buildLibrary(r'''
import 'append.dart';
import 'order.dart';

@DeclareInType('  A1.named12();')
class A1 {
  A1.named11();
}

@DeclarationsIntrospectConstructors('A1')
class A2 {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

augment class A1 {
  A1.named12();
}
augment class A2 {
  void introspected_A1_named11();
  void introspected_A1_named12();
}
''');
  }

  test_declarations_class_constructorsOf_cycle2() async {
    var library = await buildLibrary(r'''
import 'order.dart';

@DeclarationsIntrospectConstructors('A2')
class A1 {}

@DeclarationsIntrospectConstructors('A1')
class A2 {}

@DeclarationsIntrospectConstructors('A1')
@DeclarationsIntrospectConstructors('A2')
class A3 {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;

    // Note, the errors are also reported when introspecting `A1` and `A2`
    // during running macro applications on `A3`, because we know that
    // `A1` and `A2` declarations are incomplete.
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  definingUnit
    classes
      class A1 @70
        macroDiagnostics
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 0
            introspectedElement: self::@class::A2
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A1
                annotationIndex: 0
                introspectedElement: self::@class::A2
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A1
      class A2 @125
        macroDiagnostics
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 0
            introspectedElement: self::@class::A1
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A1
                annotationIndex: 0
                introspectedElement: self::@class::A2
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A1
      class A3 @222
        macroDiagnostics
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 1
            introspectedElement: self::@class::A2
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A1
                annotationIndex: 0
                introspectedElement: self::@class::A2
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A1
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 0
            introspectedElement: self::@class::A1
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A1
                annotationIndex: 0
                introspectedElement: self::@class::A2
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A1
''');
  }

  test_declarations_class_constructorsOf_notYetDone() async {
    var library = await buildLibrary(r'''
import 'append.dart';
import 'order.dart';

@DeclarationsIntrospectConstructors('A2')
class A1 {
}

@DeclareInType('  A2.named23();')
class A2 {
  @DeclareInType('  A2.named22();')
  A2.named21();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

augment class A2 {
  A2.named22();
  A2.named23();
}
augment class A1 {
  void introspected_A2_named21();
  void introspected_A2_named22();
  void introspected_A2_named23();
}
''');
  }

  test_declarations_class_fieldsOf_alreadyDone() async {
    var library = await buildLibrary(r'''
import 'append.dart';
import 'order.dart';

@DeclareInType('  int f12 = 0;')
class A1 {
  int f11 = 0;
}

@DeclarationsIntrospectFields('A1')
class A2 {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

augment class A1 {
  int f12 = 0;
}
augment class A2 {
  void introspected_A1_f11();
  void introspected_A1_f12();
}
''');
  }

  test_declarations_class_fieldsOf_cycle2() async {
    var library = await buildLibrary(r'''
import 'order.dart';

@DeclarationsIntrospectFields('A2')
class A1 {}

@DeclarationsIntrospectFields('A1')
class A2 {}

@DeclarationsIntrospectFields('A1')
@DeclarationsIntrospectFields('A2')
class A3 {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  definingUnit
    classes
      class A1 @64
        macroDiagnostics
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 0
            introspectedElement: self::@class::A2
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A1
                annotationIndex: 0
                introspectedElement: self::@class::A2
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A1
      class A2 @113
        macroDiagnostics
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 0
            introspectedElement: self::@class::A1
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A1
                annotationIndex: 0
                introspectedElement: self::@class::A2
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A1
      class A3 @198
        macroDiagnostics
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 1
            introspectedElement: self::@class::A2
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A1
                annotationIndex: 0
                introspectedElement: self::@class::A2
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A1
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 0
            introspectedElement: self::@class::A1
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A1
                annotationIndex: 0
                introspectedElement: self::@class::A2
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A1
''');
  }

  test_declarations_class_fieldsOf_notYetDone() async {
    var library = await buildLibrary(r'''
import 'append.dart';
import 'order.dart';

@DeclarationsIntrospectFields('A2')
class A1 {}

@DeclareInType('  int f23 = 0;')
class A2 {
  @DeclareInType('  int f22 = 0;')
  int f21 = 0;
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

augment class A2 {
  int f22 = 0;
  int f23 = 0;
}
augment class A1 {
  void introspected_A2_f21();
  void introspected_A2_f22();
  void introspected_A2_f23();
}
''');
  }

  test_declarations_class_methodsOf_alreadyDone() async {
    var library = await buildLibrary(r'''
import 'append.dart';
import 'order.dart';

@DeclareInType('  void f12() {}')
class A1 {
  void f11() {}
}

@DeclarationsIntrospectMethods('A1')
class A2 {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

augment class A1 {
  void f12() {}
}
augment class A2 {
  void introspected_A1_f11();
  void introspected_A1_f12();
}
''');
  }

  test_declarations_class_methodsOf_cycle2() async {
    var library = await buildLibrary(r'''
import 'order.dart';

@DeclarationsIntrospectMethods('A2')
class A1 {}

@DeclarationsIntrospectMethods('A1')
class A2 {}

@DeclarationsIntrospectMethods('A1')
@DeclarationsIntrospectMethods('A2')
class A3 {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  definingUnit
    classes
      class A1 @65
        macroDiagnostics
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 0
            introspectedElement: self::@class::A2
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A1
                annotationIndex: 0
                introspectedElement: self::@class::A2
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A1
      class A2 @115
        macroDiagnostics
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 0
            introspectedElement: self::@class::A1
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A1
                annotationIndex: 0
                introspectedElement: self::@class::A2
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A1
      class A3 @202
        macroDiagnostics
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 1
            introspectedElement: self::@class::A2
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A1
                annotationIndex: 0
                introspectedElement: self::@class::A2
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A1
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 0
            introspectedElement: self::@class::A1
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A1
                annotationIndex: 0
                introspectedElement: self::@class::A2
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A1
''');
  }

  test_declarations_class_methodsOf_cycle2_withHead() async {
    var library = await buildLibrary(r'''
import 'order.dart';

@DeclarationsIntrospectMethods('A2')
class A1 {}

@DeclarationsIntrospectMethods('A3')
class A2 {}

@DeclarationsIntrospectMethods('A2')
class A3 {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  definingUnit
    classes
      class A1 @65
        macroDiagnostics
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 0
            introspectedElement: self::@class::A2
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A3
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A3
                annotationIndex: 0
                introspectedElement: self::@class::A2
      class A2 @115
        macroDiagnostics
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 0
            introspectedElement: self::@class::A3
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A3
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A3
                annotationIndex: 0
                introspectedElement: self::@class::A2
      class A3 @165
        macroDiagnostics
          DeclarationsIntrospectionCycleDiagnostic
            annotationIndex: 0
            introspectedElement: self::@class::A2
            components
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A2
                annotationIndex: 0
                introspectedElement: self::@class::A3
              DeclarationsIntrospectionCycleComponent
                element: self::@class::A3
                annotationIndex: 0
                introspectedElement: self::@class::A2
''');
  }

  test_declarations_class_methodsOf_notYetDone() async {
    var library = await buildLibrary(r'''
import 'append.dart';
import 'order.dart';

@DeclarationsIntrospectMethods('A2')
class A1 {}

@DeclareInType('  void f23() {}')
class A2 {
  @DeclareInType('  void f22() {}')
  void f21() {}
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

augment class A2 {
  void f22() {}
  void f23() {}
}
augment class A1 {
  void introspected_A2_f21();
  void introspected_A2_f22();
  void introspected_A2_f23();
}
''');
  }

  test_declarations_class_methodsOf_self() async {
    var library = await buildLibrary(r'''
import 'order.dart';

@DeclarationsIntrospectMethods('A')
class A {
  void foo() {}
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

augment class A {
  void introspected_A_foo();
}
''');
  }

  test_phases_class_types_declarations() async {
    var library = await buildLibrary(r'''
import 'order.dart';

@AddClass('A1')
@AddFunction('f1')
class X {}
''');

    configuration.forOrder();
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class A1 {}
void f1() {}
---
''');
  }

  test_types_class_method_rightToLeft() async {
    var library = await buildLibrary(r'''
import 'order.dart';

class X {
  @AddClass('A1')
  @AddClass('A2')
  void foo() {}
}
''');

    configuration.forOrder();
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class A2 {}
class A1 {}
---
''');
  }

  test_types_class_method_sourceOrder() async {
    var library = await buildLibrary(r'''
import 'order.dart';

class X {
  @AddClass('A1')
  void foo() {}

  @AddClass('A2')
  void bar() {}
}
''');

    configuration.forOrder();
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class A1 {}
class A2 {}
---
''');
  }

  test_types_class_rightToLeft() async {
    var library = await buildLibrary(r'''
import 'order.dart';

@AddClass('A1')
@AddClass('A2')
class X {}
''');

    configuration.forOrder();
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class A2 {}
class A1 {}
---
''');
  }

  test_types_class_sourceOrder() async {
    var library = await buildLibrary(r'''
import 'order.dart';

@AddClass('A1')
class X1 {}

@AddClass('A2')
class X2 {}
''');

    configuration.forOrder();
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class A1 {}
class A2 {}
---
''');
  }

  test_types_enum() async {
    var library = await buildLibrary(r'''
import 'order.dart';

@AddClass('A1')
enum X {
  @AddClass('A2')
  v1,
  @AddClass('A3')
  v2;
  @AddClass('A4')
  void foo() {}
}
''');

    configuration.forOrder();
    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

class A2 {}
class A3 {}
class A4 {}
class A1 {}
''');
  }

  test_types_innerBeforeOuter_class_method() async {
    var library = await buildLibrary(r'''
import 'order.dart';

@AddClass('A1')
class X {
  @AddClass('A2')
  void foo() {}
}
''');

    configuration.forOrder();
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class A2 {}
class A1 {}
---
''');
  }

  test_types_innerBeforeOuter_mixin_method() async {
    var library = await buildLibrary(r'''
import 'order.dart';

@AddClass('A1')
mixin X {
  @AddClass('A2')
  void foo() {}
}
''');

    configuration.forOrder();
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class A2 {}
class A1 {}
---
''');
  }

  test_types_libraryDirective_last() async {
    var library = await buildLibrary(r'''
@AddClass('A1')
library;

import 'order.dart';

@AddClass('A2')
class X {}
''');

    configuration.forOrder();
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class A2 {}
class A1 {}
---
''');
  }

  test_types_mixin_method_rightToLeft() async {
    var library = await buildLibrary(r'''
import 'order.dart';

mixin X {
  @AddClass('A1')
  @AddClass('A2')
  void foo() {}
}
''');

    configuration.forOrder();
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class A2 {}
class A1 {}
---
''');
  }

  test_types_mixin_method_sourceOrder() async {
    var library = await buildLibrary(r'''
import 'order.dart';

mixin X {
  @AddClass('A1')
  void foo() {}

  @AddClass('A2')
  void bar() {}
}
''');

    configuration.forOrder();
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class A1 {}
class A2 {}
---
''');
  }

  test_types_mixin_rightToLeft() async {
    var library = await buildLibrary(r'''
import 'order.dart';

@AddClass('A1')
@AddClass('A2')
mixin X {}
''');

    configuration.forOrder();
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class A2 {}
class A1 {}
---
''');
  }

  test_types_mixin_sourceOrder() async {
    var library = await buildLibrary(r'''
import 'order.dart';

@AddClass('A1')
mixin X1 {}

@AddClass('A2')
mixin X2 {}
''');

    configuration.forOrder();
    checkElementText(library, r'''
library
  imports
    package:test/order.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class A1 {}
class A2 {}
---
''');
  }
}

@reflectiveTest
class MacroApplicationOrderTest_fromBytes extends MacroApplicationOrderTest {
  @override
  bool get keepLinkingLibraries => false;
}

@reflectiveTest
class MacroApplicationOrderTest_keepLinking extends MacroApplicationOrderTest {
  @override
  bool get keepLinkingLibraries => true;
}

@reflectiveTest
class MacroArgumentsTest extends MacroElementsBaseTest {
  @override
  bool get keepLinkingLibraries => true;

  @TestTimeout(Timeout(Duration(seconds: 60)))
  test_error() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'Object',
        'bar': 'Object',
      },
      constructorParametersCode: '(this.foo, this.bar)',
      argumentsCode: '(0, const Object())',
      hasErrors: true,
      expected: r'''
library
  imports
    package:test/arguments_text.dart
  definingUnit
    classes
      class A @76
        macroDiagnostics
          ArgumentMacroDiagnostic
            annotationIndex: 0
            argumentIndex: 1
            message: Not supported: InstanceCreationExpressionImpl
''',
    );
  }

  test_kind_named_positional() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'List<int>',
        'bar': 'List<double>',
      },
      constructorParametersCode: '(this foo, {required this.bar})',
      argumentsCode: '(bar: [0.1], [2])',
      expected: r'''
foo: List<int> [2]
bar: List<double> [0.1]
''',
    );
  }

  test_kind_optionalNamed() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'int',
        'bar': 'int',
      },
      constructorParametersCode: '({this.foo = -1, this.bar = -2})',
      argumentsCode: '(foo: 1)',
      expected: r'''
foo: int 1
bar: int -2
''',
    );
  }

  test_kind_optionalPositional() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'int',
        'bar': 'int',
      },
      constructorParametersCode: '([this.foo = -1, this.bar = -2])',
      argumentsCode: '(1)',
      expected: r'''
foo: int 1
bar: int -2
''',
    );
  }

  test_kind_requiredNamed() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'int'},
      constructorParametersCode: '({required this.foo})',
      argumentsCode: '(foo: 42)',
      expected: r'''
foo: int 42
''',
    );
  }

  test_kind_requiredPositional() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'int'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: '(42)',
      expected: r'''
foo: int 42
''',
    );
  }

  test_type_bool() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'bool',
        'bar': 'bool',
      },
      constructorParametersCode: '(this.foo, this.bar)',
      argumentsCode: '(true, false)',
      expected: r'''
foo: bool true
bar: bool false
''',
    );
  }

  test_type_double() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'double'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: '(1.2)',
      expected: r'''
foo: double 1.2
''',
    );
  }

  test_type_double_negative() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'double'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: '(-1.2)',
      expected: r'''
foo: double -1.2
''',
    );
  }

  test_type_int() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'int'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: '(42)',
      expected: r'''
foo: int 42
''',
    );
  }

  test_type_int_negative() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'int'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: '(-42)',
      expected: r'''
foo: int -42
''',
    );
  }

  test_type_list_int() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'List<int>',
      },
      constructorParametersCode: '(this.foo)',
      argumentsCode: '([0, 1, 2])',
      expected: r'''
foo: List<int> [0, 1, 2]
''',
    );
  }

  test_type_list_intQ() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'List<int?>',
      },
      constructorParametersCode: '(this.foo)',
      argumentsCode: '([0, null, 2])',
      expected: r'''
foo: List<int?> [0, null, 2]
''',
    );
  }

  test_type_list_map_int_string() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'List<Map<int, String>>',
      },
      constructorParametersCode: '(this.foo)',
      argumentsCode: '([{0: "a"}, {1: "b", 2: "c"}])',
      expected: r'''
foo: List<Map<int, String>> [{0: a}, {1: b, 2: c}]
''',
    );
  }

  test_type_list_objectQ() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'List<Object?>',
      },
      constructorParametersCode: '(this.foo)',
      argumentsCode: '([1, 2, true, 3, 4.2])',
      expected: r'''
foo: List<Object?> [1, 2, true, 3, 4.2]
''',
    );
  }

  test_type_map_int_string() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'Map<int, String>',
      },
      constructorParametersCode: '(this.foo)',
      argumentsCode: '({0: "a", 1: "b"})',
      expected: r'''
foo: _Map<int, String> {0: a, 1: b}
''',
    );
  }

  test_type_null() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'Object?'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: '(null)',
      expected: r'''
foo: Null null
''',
    );
  }

  test_type_set() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'Set<int>',
      },
      constructorParametersCode: '(this.foo)',
      argumentsCode: '({1, 2, 3})',
      expected: r'''
foo: _Set<int> {1, 2, 3}
''',
    );
  }

  test_type_string() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'String'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: "('aaa')",
      expected: r'''
foo: String aaa
''',
    );
  }

  test_type_string_adjacent() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'String'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: "('aaa' 'bbb' 'ccc')",
      expected: r'''
foo: String aaabbbccc
''',
    );
  }

  /// Build a macro with specified [fields], initialized in the constructor
  /// with [constructorParametersCode], and apply this macro  with
  /// [argumentsCode] to an empty class.
  ///
  /// The macro generates exactly one top-level constant `x`, with a textual
  /// dump of the field values. So, we check that the analyzer built these
  /// values, and the macro executor marshalled these values to the running
  /// macro isolate.
  Future<void> _assertTypesPhaseArgumentsText({
    required Map<String, String> fields,
    required String constructorParametersCode,
    required String argumentsCode,
    required String expected,
    bool hasErrors = false,
  }) async {
    var dumpCode = fields.keys.map((name) {
      return "$name: \${$name.runtimeType} \$$name\\\\n";
    }).join();

    newFile('$testPackageLibPath/arguments_text.dart', '''
import 'dart:async';
import 'package:macros/macros.dart';

macro class ArgumentsTextMacro implements ClassTypesMacro {
${fields.entries.map((e) => '  final ${e.value} ${e.key};').join('\n')}

  const ArgumentsTextMacro${constructorParametersCode.trim()};

  FutureOr<void> buildTypesForClass(clazz, builder) {
    builder.declareType(
      'x',
      DeclarationCode.fromString(
        "const x = '$dumpCode';",
      ),
    );
  }
}
''');

    var library = await buildLibrary('''
import 'arguments_text.dart';

@ArgumentsTextMacro$argumentsCode
class A {}
''');

    if (hasErrors) {
      configuration
        ..withConstructors = false
        ..withMetadata = false;
      checkElementText(library, expected);
    } else {
      if (library.allMacroDiagnostics.isNotEmpty) {
        failWithLibraryText(library);
      }

      var x = library.topLevelElements
          .whereType<ConstTopLevelVariableElementImpl>()
          .single;
      expect(x.name, 'x');
      var actual = (x.constantInitializer as SimpleStringLiteral).value;
      if (actual != expected) {
        print('-------- Actual --------');
        print('$actual------------------------');
        NodeTextExpectationsCollector.add(actual);
      }
      expect(actual, expected);
    }
  }
}

@reflectiveTest
class MacroCodeGenerationTest extends MacroElementsBaseTest {
  @override
  bool get keepLinkingLibraries => true;

  @override
  Future<void> setUp() async {
    await super.setUp();

    newFile(
      '$testPackageLibPath/code_generation.dart',
      _getMacroCode('code_generation.dart'),
    );
  }

  test_class_addMethod2_augmentMethod2() async {
    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareInType("""
  @{{package:test/append.dart@AugmentDefinition}}('{}')
  void foo();""")
@DeclareInType("""
  @{{package:test/append.dart@AugmentDefinition}}('{}')
  void bar();""")
class A {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/append.dart' as prefix0;

augment class A {
  @prefix0.AugmentDefinition('{}')
  void bar();
  @prefix0.AugmentDefinition('{}')
  void foo();
  augment void foo() {}
  augment void bar() {}
}
''');
  }

  test_declarationsPhase_metadata_class_type() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@DeclarationsPhaseAnnotationType()
@A()
class X {}

class A {
  const A();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/test.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_declarationsPhase_metadata_class_type_imported() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@DeclarationsPhaseAnnotationType()
@A()
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/a.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_declarationsPhase_metadata_class_type_imported_withPrefix() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart' as prefix;

@DeclarationsPhaseAnnotationType()
@prefix.A()
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/a.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_declarationsPhase_metadata_classAlias() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@DeclarationsPhaseAnnotationType()
@A()
class X = Object with M;

class A {
  const A();
}

mixin M {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/test.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_declarationsPhase_metadata_classConstructor() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class X {
  @DeclarationsPhaseAnnotationType()
  @A()
  X();
}

class A {
  const A();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/test.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_declarationsPhase_metadata_classField() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class X {
  @DeclarationsPhaseAnnotationType()
  @A()
  final foo = 0;
}

class A {
  const A();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/test.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_declarationsPhase_metadata_classMethod() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class X {
  @DeclarationsPhaseAnnotationType()
  @A()
  void foo() {}
}

class A {
  const A();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/test.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_declarationsPhase_metadata_enum() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@DeclarationsPhaseAnnotationType()
@A()
enum X {v}

class A {
  const A();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/test.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_declarationsPhase_metadata_extension() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@DeclarationsPhaseAnnotationType()
@A()
extension X on int {}

class A {
  const A();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/test.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_declarationsPhase_metadata_extensionType() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@DeclarationsPhaseAnnotationType()
@A()
extension type X(int it) {}

class A {
  const A();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/test.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_declarationsPhase_metadata_function() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@DeclarationsPhaseAnnotationType()
@A()
void foo() {}

class A {
  const A();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/test.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_declarationsPhase_metadata_mixin() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@DeclarationsPhaseAnnotationType()
@A()
mixin X {}

class A {
  const A();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/test.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_declarationsPhase_metadata_topLevelVariable() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@DeclarationsPhaseAnnotationType()
@A()
final foo = 0;

class A {
  const A();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/test.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_declarationsPhase_metadata_typeAlias() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@DeclarationsPhaseAnnotationType()
@A()
typedef X = int;

class A {
  const A();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/code_generation.dart' as prefix0;
import 'package:test/test.dart' as prefix1;

var x = [prefix0.DeclarationsPhaseAnnotationType, prefix1.A];
''');
  }

  test_inferOmittedType_fieldInstance_type() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class A {
  num? foo = 42;
}

class B extends A {
  @AugmentForOmittedTypes()
  var foo;
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class B {
  augment prefix0.num? foo = 0;
}
''');
  }

  test_inferOmittedType_fieldStatic_type() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class A {
  @AugmentForOmittedTypes()
  static var foo;
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class A {
  augment static prefix0.dynamic foo = 0;
}
''');
  }

  test_inferOmittedType_function_returnType() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@AugmentForOmittedTypes()
foo() {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment prefix0.dynamic foo() {}
''');
  }

  test_inferOmittedType_functionType_returnType() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@AugmentForOmittedTypes()
void foo(Function() a) {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment void foo(prefix0.dynamic Function() a, ) {}
''');
  }

  test_inferOmittedType_getterInstance_returnType() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class A {
  int get foo => 0;
}

class B extends A {
  @AugmentForOmittedTypes()
  get foo => 0;
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class B {
  augment prefix0.int get foo {}
}
''');
  }

  test_inferOmittedType_methodInstance_formalParameter() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class A {
  void foo(int a) {}
}

class B extends A {
  @AugmentForOmittedTypes()
  void foo(a) {}
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class B {
  augment void foo(prefix0.int a, ) {}
}
''');
  }

  test_inferOmittedType_methodInstance_returnType() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class A {
  int foo() => 0;
}

class B extends A {
  @AugmentForOmittedTypes()
  foo() {}
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class B {
  augment prefix0.int foo() {}
}
''');
  }

  test_inferOmittedType_methodStatic_formalParameter() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class A {
  @AugmentForOmittedTypes()
  static void foo(a) {}
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class A {
  augment static void foo(prefix0.dynamic a, ) {}
}
''');
  }

  test_inferOmittedType_methodStatic_returnType() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class A {
  @AugmentForOmittedTypes()
  static foo() {}
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class A {
  augment static prefix0.dynamic foo() {}
}
''');
  }

  test_inferOmittedType_setterInstance_formalParameter() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class A {
  void set foo(int a) {}
}

class B extends A {
  @AugmentForOmittedTypes()
  void set foo(a) {}
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class B {
  augment void set foo(prefix0.int a, ) {}
}
''');
  }

  test_inferOmittedType_setterInstance_returnType() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class A {
  @AugmentForOmittedTypes()
  set foo(int _) {}
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class A {
  augment void set foo(prefix0.int _, ) {}
}
''');
  }

  test_inferOmittedType_setterStatic_formalParameter() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class A {
  @AugmentForOmittedTypes()
  static void set foo(a) {}
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class A {
  augment static void set foo(prefix0.dynamic a, ) {}
}
''');
  }

  test_inferOmittedType_setterStatic_returnType() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class A {
  @AugmentForOmittedTypes()
  static set foo(int _) {}
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class A {
  augment static void set foo(prefix0.int _, ) {}
}
''');
  }

  test_macroGeneratedFile_existedBeforeLinking() async {
    // See https://github.com/dart-lang/sdk/issues/54713
    // Create `FileState` with the same name as would be macro generated.
    // If we don't have implementation to discard it, we will get exception.
    var macroFile = getFile('$testPackageLibPath/test.macro.dart');
    driverFor(testFile).getFileSync2(macroFile);

    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareTypesPhase('B', 'class B {}')
class A {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

class B {}
''');
  }

  test_resolveIdentifier_class() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'A')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A;
  }
}
''');
  }

  test_resolveIdentifier_class_constructor() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  A.named();
}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'A', memberName: 'named')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A.named;
  }
}
''');
  }

  test_resolveIdentifier_class_constructor_fromPart() async {
    newFile('$testPackageLibPath/a.dart', r'''
part 'b.dart';
''');

    newFile('$testPackageLibPath/b.dart', r'''
part of 'a.dart';
class A {
  A.named();
}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'A', memberName: 'named')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A.named;
  }
}
''');
  }

  test_resolveIdentifier_class_exported() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {}
''');

    newFile('$testPackageLibPath/b.dart', r'''
export 'a.dart';
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'b.dart';

@ReferenceIdentifier('package:test/b.dart', 'A')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A;
  }
}
''');
  }

  test_resolveIdentifier_class_field_instance() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  int foo = 0;
}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier(
  'package:test/a.dart',
  'A',
  memberName: 'foo',
  parametersCode: 'dynamic a',
  leadCode: 'a.',
)
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

augment class X {
  void doReference(dynamic a) {
    a.foo;
  }
}
''');
  }

  test_resolveIdentifier_class_field_static() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  static int foo = 0;
}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'A', memberName: 'foo')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A.foo;
  }
}
''');
  }

  test_resolveIdentifier_class_field_static_fromPart() async {
    newFile('$testPackageLibPath/a.dart', r'''
part 'b.dart';
''');

    newFile('$testPackageLibPath/b.dart', r'''
part of 'a.dart';
class A {
  static int foo = 0;
}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'A', memberName: 'foo')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A.foo;
  }
}
''');
  }

  test_resolveIdentifier_class_fromPart() async {
    newFile('$testPackageLibPath/a.dart', r'''
part 'b.dart';
''');

    newFile('$testPackageLibPath/b.dart', r'''
part of 'a.dart';
class B {}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'B')
class A {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class A {
  void doReference() {
    prefix0.B;
  }
}
''');
  }

  test_resolveIdentifier_class_getter_instance() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  int get foo => 0;
}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier(
  'package:test/a.dart',
  'A',
  memberName: 'foo',
  parametersCode: 'dynamic a',
  leadCode: 'a.',
)
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

augment class X {
  void doReference(dynamic a) {
    a.foo;
  }
}
''');
  }

  test_resolveIdentifier_class_getter_static() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  static int get foo => 0;
}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'A', memberName: 'foo')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A.foo;
  }
}
''');
  }

  test_resolveIdentifier_class_getter_static_fromPart() async {
    newFile('$testPackageLibPath/a.dart', r'''
part 'b.dart';
''');

    newFile('$testPackageLibPath/b.dart', r'''
part of 'a.dart';
class A {
  static int get foo => 0;
}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'A', memberName: 'foo')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A.foo;
  }
}
''');
  }

  test_resolveIdentifier_class_method_instance() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  void foo() {}
}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier(
  'package:test/a.dart',
  'A',
  memberName: 'foo',
  parametersCode: 'dynamic a',
  leadCode: 'a.',
)
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

augment class X {
  void doReference(dynamic a) {
    a.foo;
  }
}
''');
  }

  test_resolveIdentifier_class_method_static() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  static void foo() {}
}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'A', memberName: 'foo')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A.foo;
  }
}
''');
  }

  test_resolveIdentifier_class_method_static_fromPart() async {
    newFile('$testPackageLibPath/a.dart', r'''
part 'b.dart';
''');

    newFile('$testPackageLibPath/b.dart', r'''
part of 'a.dart';
class A {
  static void foo() {}
}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'A', memberName: 'foo')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A.foo;
  }
}
''');
  }

  test_resolveIdentifier_extension() async {
    newFile('$testPackageLibPath/a.dart', r'''
extension A on int {}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'A')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A;
  }
}
''');
  }

  test_resolveIdentifier_extensionType() async {
    newFile('$testPackageLibPath/a.dart', r'''
extension type A(int it) {}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'A')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A;
  }
}
''');
  }

  test_resolveIdentifier_formalParameter() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@ReferenceFirstFormalParameter()
void foo(int a);
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment void foo(prefix0.int a, ) {
  a;
}
''');
  }

  test_resolveIdentifier_functionTypeAlias() async {
    newFile('$testPackageLibPath/a.dart', r'''
typedef void A();
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'A')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A;
  }
}
''');
  }

  test_resolveIdentifier_genericTypeAlias() async {
    newFile('$testPackageLibPath/a.dart', r'''
typedef A = int;
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'A')
class X {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  void doReference() {
    prefix0.A;
  }
}
''');
  }

  test_resolveIdentifier_typeParameter() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@ReferenceFirstTypeParameter()
void foo<T>();
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

augment void foo<T>() {
  T;
}
''');
  }

  test_resolveIdentifier_unit_function() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo() {}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'foo')
class A {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class A {
  void doReference() {
    prefix0.foo;
  }
}
''');
  }

  test_resolveIdentifier_unit_function_fromPart() async {
    newFile('$testPackageLibPath/a.dart', r'''
part 'b.dart';
''');

    newFile('$testPackageLibPath/b.dart', r'''
part of 'a.dart';
void foo() {}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'foo')
class A {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class A {
  void doReference() {
    prefix0.foo;
  }
}
''');
  }

  test_resolveIdentifier_unit_getter() async {
    newFile('$testPackageLibPath/a.dart', r'''
int get foo => 0;
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'foo')
class A {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class A {
  void doReference() {
    prefix0.foo;
  }
}
''');
  }

  test_resolveIdentifier_unit_getter_fromPart() async {
    newFile('$testPackageLibPath/a.dart', r'''
part 'b.dart';
''');

    newFile('$testPackageLibPath/b.dart', r'''
part of 'a.dart';
int get foo => 0;
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'foo')
class A {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class A {
  void doReference() {
    prefix0.foo;
  }
}
''');
  }

  test_resolveIdentifier_unit_setter() async {
    newFile('$testPackageLibPath/a.dart', r'''
set foo(int value) {}
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'foo=')
class A {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class A {
  void doReference() {
    prefix0.foo;
  }
}
''');
  }

  test_resolveIdentifier_unit_setter_exported() async {
    newFile('$testPackageLibPath/a.dart', r'''
set foo(int value) {}
''');

    newFile('$testPackageLibPath/b.dart', r'''
export 'a.dart';
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'b.dart';

@ReferenceIdentifier('package:test/b.dart', 'foo=')
class A {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class A {
  void doReference() {
    prefix0.foo;
  }
}
''');
  }

  test_resolveIdentifier_unit_variable() async {
    newFile('$testPackageLibPath/a.dart', r'''
var foo = 0;
''');

    var library = await buildLibrary(r'''
import 'code_generation.dart';
import 'a.dart';

@ReferenceIdentifier('package:test/a.dart', 'foo')
class A {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class A {
  void doReference() {
    prefix0.foo;
  }
}
''');
  }

  test_toStringAsTypeName_atClass() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

@DefineToStringAsTypeName()
class A {
  String toString();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class A {
  augment prefix0.String toString() {
    return 'A';
  }
}
''');
  }

  test_toStringAsTypeName_atMethod() async {
    var library = await buildLibrary(r'''
import 'code_generation.dart';

class A {
  @DefineToStringAsTypeName()
  String toString();
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class A {
  augment prefix0.String toString() => 'A';
}
''');
  }
}

abstract class MacroDeclarationsTest extends MacroElementsBaseTest {
  test_addClass_addMethod_addMethod() async {
    _addSingleMacro('addClass_addMethod_addMethod.dart');

    var library = await buildLibrary(r'''
import 'a.dart';

@AddClassB()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/a.dart
  definingUnit
    reference: self
    classes
      class A @37
        reference: self::@class::A
        metadata
          Annotation
            atSign: @ @18
            name: SimpleIdentifier
              token: AddClassB @19
              staticElement: package:test/a.dart::@class::AddClassB
              staticType: null
            arguments: ArgumentList
              leftParenthesis: ( @28
              rightParenthesis: ) @29
            element: package:test/a.dart::@class::AddClassB::@constructor::new
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.AddMethodFoo()
class B {}

augment class B {
  @prefix0.AddMethodBar()
  void foo() {}
  void bar() {}
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          class B @115
            reference: self::@augmentation::package:test/test.macro.dart::@class::B
            metadata
              Annotation
                atSign: @ @85
                name: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @86
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @93
                  identifier: SimpleIdentifier
                    token: AddMethodFoo @94
                    staticElement: package:test/a.dart::@class::AddMethodFoo
                    staticType: null
                  staticElement: package:test/a.dart::@class::AddMethodFoo
                  staticType: null
                arguments: ArgumentList
                  leftParenthesis: ( @106
                  rightParenthesis: ) @107
                element: package:test/a.dart::@class::AddMethodFoo::@constructor::new
            augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::B
            augmented
              methods
                self::@augmentation::package:test/test.macro.dart::@classAugmentation::B::@method::bar
                self::@augmentation::package:test/test.macro.dart::@classAugmentation::B::@method::foo
          augment class B @135
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::B
            augmentationTarget: self::@augmentation::package:test/test.macro.dart::@class::B
            methods
              foo @172
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::B::@method::foo
                metadata
                  Annotation
                    atSign: @ @141
                    name: PrefixedIdentifier
                      prefix: SimpleIdentifier
                        token: prefix0 @142
                        staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                        staticType: null
                      period: . @149
                      identifier: SimpleIdentifier
                        token: AddMethodBar @150
                        staticElement: package:test/a.dart::@class::AddMethodBar
                        staticType: null
                      staticElement: package:test/a.dart::@class::AddMethodBar
                      staticType: null
                    arguments: ArgumentList
                      leftParenthesis: ( @162
                      rightParenthesis: ) @163
                    element: package:test/a.dart::@class::AddMethodBar::@constructor::new
                returnType: void
              bar @188
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::B::@method::bar
                returnType: void
''');
  }

  test_class_constructor_add_fieldFormalParameter() async {
    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareInType('  A.named(this.f);')
class A {
  final int f;
}
''');

    configuration
      ..withMetadata = false
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/append.dart
  definingUnit
    reference: self
    classes
      class A @66
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        fields
          final f @82
            reference: self::@class::A::@field::f
            type: int
        accessors
          synthetic get f @-1
            reference: self::@class::A::@getter::f
            returnType: int
        augmented
          fields
            self::@class::A::@field::f
          constructors
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructor::named
          accessors
            self::@class::A::@getter::f
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

augment class A {
  A.named(this.f);
}
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @57
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            constructors
              named @65
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructor::named
                periodOffset: 64
                nameEnd: 70
                parameters
                  requiredPositional final this.f @76
                    type: int
                    field: self::@class::A::@field::f
''');
  }

  test_class_constructor_add_named() async {
    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareInType('  A.named(int a);')
class A {}
''');

    configuration
      ..withMetadata = false
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/append.dart
  definingUnit
    reference: self
    classes
      class A @65
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        augmented
          constructors
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructor::named
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

augment class A {
  A.named(int a);
}
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @57
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            constructors
              named @65
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructor::named
                periodOffset: 64
                nameEnd: 70
                parameters
                  requiredPositional a @75
                    type: int
''');
  }

  test_class_constructor_add_unnamed() async {
    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareInType('  A(int a);')
class A {}
''');

    configuration
      ..withMetadata = false
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/append.dart
  definingUnit
    reference: self
    classes
      class A @59
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        augmented
          constructors
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructor::new
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

augment class A {
  A(int a);
}
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @57
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            constructors
              @63
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructor::new
                parameters
                  requiredPositional a @69
                    type: int
''');
  }

  test_class_field_add() async {
    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareInType('  int foo = 0;')
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/append.dart
  definingUnit
    reference: self
    classes
      class A @62
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        augmented
          fields
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@field::foo
          accessors
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@getter::foo
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@setter::foo
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

augment class A {
  int foo = 0;
}
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @57
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            fields
              foo @67
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@field::foo
                type: int
                shouldUseTypeForInitializerInference: true
            accessors
              synthetic get foo @-1
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@getter::foo
                returnType: int
              synthetic set foo= @-1
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@setter::foo
                parameters
                  requiredPositional _foo @-1
                    type: int
                returnType: void
''');
  }

  test_class_getter_add() async {
    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareInType('  int get foo => 0;')
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/append.dart
  definingUnit
    reference: self
    classes
      class A @67
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        augmented
          fields
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@field::foo
          accessors
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@getter::foo
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

augment class A {
  int get foo => 0;
}
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @57
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            fields
              synthetic foo @-1
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@field::foo
                type: int
            accessors
              get foo @71
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@getter::foo
                returnType: int
''');
  }

  test_class_method_add() async {
    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareInType('  int foo(double a) => 0;')
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/append.dart
  definingUnit
    reference: self
    classes
      class A @73
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        augmented
          methods
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@method::foo
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

augment class A {
  int foo(double a) => 0;
}
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @57
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            methods
              foo @67
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@method::foo
                parameters
                  requiredPositional a @78
                    type: double
                returnType: int
''');
  }

  test_class_setter_add() async {
    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareInType('  set foo(int a) {}')
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/append.dart
  definingUnit
    reference: self
    classes
      class A @67
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        augmented
          fields
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@field::foo
          accessors
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@setter::foo
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

augment class A {
  set foo(int a) {}
}
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @57
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            fields
              synthetic foo @-1
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@field::foo
                type: int
            accessors
              set foo= @67
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@setter::foo
                parameters
                  requiredPositional a @75
                    type: int
                returnType: void
''');
  }

  test_codeOptimizer_class_constructor_optionalPositional_defaultValue() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType('  B([x = {{package:test/a.dart@a}}]);')
class B {}
''');

    configuration
      ..forCodeOptimizer()
      ..withConstructors = true;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  B([x = prefix0.a]);
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            constructors
              @105
                parameters
                  optionalPositional default x @108
                    type: dynamic
                    constantInitializer
                      PrefixedIdentifier
                        prefix: SimpleIdentifier
                          token: prefix0 @112
                          staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                          staticType: null
                        period: . @119
                        identifier: SimpleIdentifier
                          token: a @120
                          staticElement: package:test/a.dart::@getter::a
                          staticType: int
                        staticElement: package:test/a.dart::@getter::a
                        staticType: int
''');
  }

  test_codeOptimizer_class_method_optionalPositional_defaultValue() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType('  void foo([x = {{package:test/a.dart@a}}]) {}')
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  void foo([x = prefix0.a]) {}
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            methods
              foo @110
                parameters
                  optionalPositional default x @115
                    type: dynamic
                    constantInitializer
                      PrefixedIdentifier
                        prefix: SimpleIdentifier
                          token: prefix0 @119
                          staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                          staticType: null
                        period: . @126
                        identifier: SimpleIdentifier
                          token: a @127
                          staticElement: package:test/a.dart::@getter::a
                          staticType: int
                        staticElement: package:test/a.dart::@getter::a
                        staticType: int
                returnType: void
''');
  }

  test_codeOptimizer_class_method_optionalPositional_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType('  void foo([@{{package:test/a.dart@a}} x]) {}')
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  void foo([@prefix0.a x]) {}
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            methods
              foo @110
                parameters
                  optionalPositional default x @126
                    type: dynamic
                    metadata
                      Annotation
                        atSign: @ @115
                        name: PrefixedIdentifier
                          prefix: SimpleIdentifier
                            token: prefix0 @116
                            staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                            staticType: null
                          period: . @123
                          identifier: SimpleIdentifier
                            token: a @124
                            staticElement: package:test/a.dart::@getter::a
                            staticType: null
                          staticElement: package:test/a.dart::@getter::a
                          staticType: null
                        element: package:test/a.dart::@getter::a
                returnType: void
''');
  }

  test_codeOptimizer_class_method_requiredPositional_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType('  void foo(@{{package:test/a.dart@a}} x) {}')
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  void foo(@prefix0.a x) {}
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            methods
              foo @110
                parameters
                  requiredPositional x @125
                    type: dynamic
                    metadata
                      Annotation
                        atSign: @ @114
                        name: PrefixedIdentifier
                          prefix: SimpleIdentifier
                            token: prefix0 @115
                            staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                            staticType: null
                          period: . @122
                          identifier: SimpleIdentifier
                            token: a @123
                            staticElement: package:test/a.dart::@getter::a
                            staticType: null
                          staticElement: package:test/a.dart::@getter::a
                          staticType: null
                        element: package:test/a.dart::@getter::a
                returnType: void
''');
  }

  test_codeOptimizer_class_setter_requiredPositional_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType('  set foo(@{{package:test/a.dart@a}} x) {}')
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  set foo(@prefix0.a x) {}
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            fields
              synthetic foo @-1
                type: dynamic
            accessors
              set foo= @109
                parameters
                  requiredPositional x @124
                    type: dynamic
                    metadata
                      Annotation
                        atSign: @ @113
                        name: PrefixedIdentifier
                          prefix: SimpleIdentifier
                            token: prefix0 @114
                            staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                            staticType: null
                          period: . @121
                          identifier: SimpleIdentifier
                            token: a @122
                            staticElement: package:test/a.dart::@getter::a
                            staticType: null
                          staticElement: package:test/a.dart::@getter::a
                          staticType: null
                        element: package:test/a.dart::@getter::a
                returnType: void
''');
  }

  test_codeOptimizer_constant_class_field_const() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType('  static const x = {{package:test/a.dart@a}};')
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  static const x = prefix0.a;
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            fields
              static const x @118
                type: int
                shouldUseTypeForInitializerInference: false
                constantInitializer
                  PrefixedIdentifier
                    prefix: SimpleIdentifier
                      token: prefix0 @122
                      staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                      staticType: null
                    period: . @129
                    identifier: SimpleIdentifier
                      token: a @130
                      staticElement: package:test/a.dart::@getter::a
                      staticType: int
                    staticElement: package:test/a.dart::@getter::a
                    staticType: int
            accessors
              synthetic static get x @-1
                returnType: int
''');
  }

  test_codeOptimizer_constant_class_field_final_hasConstConstructor() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType('  final x = {{package:test/a.dart@a}};')
class B {
  const B();
}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  final x = prefix0.a;
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            fields
              final x @111
                type: int
                shouldUseTypeForInitializerInference: false
                constantInitializer
                  PrefixedIdentifier
                    prefix: SimpleIdentifier
                      token: prefix0 @115
                      staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                      staticType: null
                    period: . @122
                    identifier: SimpleIdentifier
                      token: a @123
                      staticElement: package:test/a.dart::@getter::a
                      staticType: int
                    staticElement: package:test/a.dart::@getter::a
                    staticType: int
            accessors
              synthetic get x @-1
                returnType: int
''');
  }

  test_codeOptimizer_constant_class_field_final_noConstConstructor() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType('  final x = {{package:test/a.dart@a}};')
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  final x = prefix0.a;
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            fields
              final x @111
                type: int
                shouldUseTypeForInitializerInference: false
            accessors
              synthetic get x @-1
                returnType: int
''');
  }

  test_codeOptimizer_constant_class_field_namedType() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A<T> {}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType('  static const x = {{package:test/a.dart@A}}<void>;')
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  static const x = prefix0.A<void>;
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            fields
              static const x @118
                type: Type
                shouldUseTypeForInitializerInference: false
                constantInitializer
                  TypeLiteral
                    type: NamedType
                      importPrefix: ImportPrefixReference
                        name: prefix0 @122
                        period: . @129
                        element: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                      name: A @130
                      typeArguments: TypeArgumentList
                        leftBracket: < @131
                        arguments
                          NamedType
                            name: void @132
                            element: <null>
                            type: void
                        rightBracket: > @136
                      element: package:test/a.dart::@class::A
                      type: A<void>
                    staticType: Type
            accessors
              synthetic static get x @-1
                returnType: Type
''');
  }

  test_codeOptimizer_constant_topVariable_constant() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInLibrary('const x = {{package:test/a.dart@a}};')
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

const x = prefix0.a;
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        topLevelVariables
          static const x @91
            type: int
            shouldUseTypeForInitializerInference: false
            constantInitializer
              PrefixedIdentifier
                prefix: SimpleIdentifier
                  token: prefix0 @95
                  staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                  staticType: null
                period: . @102
                identifier: SimpleIdentifier
                  token: a @103
                  staticElement: package:test/a.dart::@getter::a
                  staticType: int
                staticElement: package:test/a.dart::@getter::a
                staticType: int
        accessors
          synthetic static get x @-1
            returnType: int
''');
  }

  test_codeOptimizer_constant_topVariable_constant2() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
const b = 0;
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInLibrary('const x = {{package:test/a.dart@a}} + {{package:test/a.dart@b}};')
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

const x = prefix0.a + prefix0.b;
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        topLevelVariables
          static const x @91
            type: int
            shouldUseTypeForInitializerInference: false
            constantInitializer
              BinaryExpression
                leftOperand: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @95
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @102
                  identifier: SimpleIdentifier
                    token: a @103
                    staticElement: package:test/a.dart::@getter::a
                    staticType: int
                  staticElement: package:test/a.dart::@getter::a
                  staticType: int
                operator: + @105
                rightOperand: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @107
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @114
                  identifier: SimpleIdentifier
                    token: b @115
                    staticElement: package:test/a.dart::@getter::b
                    staticType: int
                  staticElement: package:test/a.dart::@getter::b
                  staticType: int
                staticElement: dart:core::@class::num::@method::+
                staticInvokeType: num Function(num)
                staticType: int
        accessors
          synthetic static get x @-1
            returnType: int
''');
  }

  test_codeOptimizer_constant_topVariable_constant3() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;

class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInLibrary("""
@{{package:test/a.dart@A}}()
const x = {{package:test/a.dart@a}}, y = {{package:test/a.dart@a}};
""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.A()
const x = prefix0.a, y = prefix0.a;

---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        topLevelVariables
          static const x @104
            metadata
              Annotation
                atSign: @ @85
                name: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @86
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @93
                  identifier: SimpleIdentifier
                    token: A @94
                    staticElement: package:test/a.dart::@class::A
                    staticType: null
                  staticElement: package:test/a.dart::@class::A
                  staticType: null
                arguments: ArgumentList
                  leftParenthesis: ( @95
                  rightParenthesis: ) @96
                element: package:test/a.dart::@class::A::@constructor::new
            type: int
            shouldUseTypeForInitializerInference: false
            constantInitializer
              PrefixedIdentifier
                prefix: SimpleIdentifier
                  token: prefix0 @108
                  staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                  staticType: null
                period: . @115
                identifier: SimpleIdentifier
                  token: a @116
                  staticElement: package:test/a.dart::@getter::a
                  staticType: int
                staticElement: package:test/a.dart::@getter::a
                staticType: int
          static const y @119
            metadata
              Annotation
                atSign: @ @85
                name: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @86
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @93
                  identifier: SimpleIdentifier
                    token: A @94
                    staticElement: package:test/a.dart::@class::A
                    staticType: null
                  staticElement: package:test/a.dart::@class::A
                  staticType: null
                arguments: ArgumentList
                  leftParenthesis: ( @95
                  rightParenthesis: ) @96
                element: package:test/a.dart::@class::A::@constructor::new
            type: int
            shouldUseTypeForInitializerInference: false
            constantInitializer
              PrefixedIdentifier
                prefix: SimpleIdentifier
                  token: prefix0 @123
                  staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                  staticType: null
                period: . @130
                identifier: SimpleIdentifier
                  token: a @131
                  staticElement: package:test/a.dart::@getter::a
                  staticType: int
                staticElement: package:test/a.dart::@getter::a
                staticType: int
        accessors
          synthetic static get x @-1
            returnType: int
          synthetic static get y @-1
            returnType: int
''');
  }

  test_codeOptimizer_constant_topVariable_namedType() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A<T> {}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInLibrary('const x = {{package:test/a.dart@A}}<void>;')
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

const x = prefix0.A<void>;
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        topLevelVariables
          static const x @91
            type: Type
            shouldUseTypeForInitializerInference: false
            constantInitializer
              TypeLiteral
                type: NamedType
                  importPrefix: ImportPrefixReference
                    name: prefix0 @95
                    period: . @102
                    element: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                  name: A @103
                  typeArguments: TypeArgumentList
                    leftBracket: < @104
                    arguments
                      NamedType
                        name: void @105
                        element: <null>
                        type: void
                    rightBracket: > @109
                  element: package:test/a.dart::@class::A
                  type: A<void>
                staticType: Type
        accessors
          synthetic static get x @-1
            returnType: Type
''');
  }

  test_codeOptimizer_metadata_class() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareTypesPhase('C', """
@{{package:test/a.dart@A}}()
class C {}""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.A()
class C {}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          class C @104
            metadata
              Annotation
                atSign: @ @85
                name: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @86
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @93
                  identifier: SimpleIdentifier
                    token: A @94
                    staticElement: package:test/a.dart::@class::A
                    staticType: null
                  staticElement: package:test/a.dart::@class::A
                  staticType: null
                arguments: ArgumentList
                  leftParenthesis: ( @95
                  rightParenthesis: ) @96
                element: package:test/a.dart::@class::A::@constructor::new
''');
  }

  test_codeOptimizer_metadata_class_constructor() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType("""
  @{{package:test/a.dart@A}}()
  B.named();""")
class B {}
''');

    configuration
      ..forCodeOptimizer()
      ..withConstructors = true;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  @prefix0.A()
  B.named();
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            constructors
              named @122
                metadata
                  Annotation
                    atSign: @ @105
                    name: PrefixedIdentifier
                      prefix: SimpleIdentifier
                        token: prefix0 @106
                        staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                        staticType: null
                      period: . @113
                      identifier: SimpleIdentifier
                        token: A @114
                        staticElement: package:test/a.dart::@class::A
                        staticType: null
                      staticElement: package:test/a.dart::@class::A
                      staticType: null
                    arguments: ArgumentList
                      leftParenthesis: ( @115
                      rightParenthesis: ) @116
                    element: package:test/a.dart::@class::A::@constructor::new
                periodOffset: 121
                nameEnd: 127
''');
  }

  test_codeOptimizer_metadata_class_field() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType("""
  @{{package:test/a.dart@A}}()
  final int foo = 0;""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  @prefix0.A()
  final int foo = 0;
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            fields
              final foo @130
                metadata
                  Annotation
                    atSign: @ @105
                    name: PrefixedIdentifier
                      prefix: SimpleIdentifier
                        token: prefix0 @106
                        staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                        staticType: null
                      period: . @113
                      identifier: SimpleIdentifier
                        token: A @114
                        staticElement: package:test/a.dart::@class::A
                        staticType: null
                      staticElement: package:test/a.dart::@class::A
                      staticType: null
                    arguments: ArgumentList
                      leftParenthesis: ( @115
                      rightParenthesis: ) @116
                    element: package:test/a.dart::@class::A::@constructor::new
                type: int
                shouldUseTypeForInitializerInference: true
            accessors
              synthetic get foo @-1
                returnType: int
''');
  }

  test_codeOptimizer_metadata_class_field2() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType("""
  @{{package:test/a.dart@A}}()
  final int foo = 0, bar = 1;""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  @prefix0.A()
  final int foo = 0, bar = 1;
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            fields
              final foo @130
                metadata
                  Annotation
                    atSign: @ @105
                    name: PrefixedIdentifier
                      prefix: SimpleIdentifier
                        token: prefix0 @106
                        staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                        staticType: null
                      period: . @113
                      identifier: SimpleIdentifier
                        token: A @114
                        staticElement: package:test/a.dart::@class::A
                        staticType: null
                      staticElement: package:test/a.dart::@class::A
                      staticType: null
                    arguments: ArgumentList
                      leftParenthesis: ( @115
                      rightParenthesis: ) @116
                    element: package:test/a.dart::@class::A::@constructor::new
                type: int
                shouldUseTypeForInitializerInference: true
              final bar @139
                metadata
                  Annotation
                    atSign: @ @105
                    name: PrefixedIdentifier
                      prefix: SimpleIdentifier
                        token: prefix0 @106
                        staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                        staticType: null
                      period: . @113
                      identifier: SimpleIdentifier
                        token: A @114
                        staticElement: package:test/a.dart::@class::A
                        staticType: null
                      staticElement: package:test/a.dart::@class::A
                      staticType: null
                    arguments: ArgumentList
                      leftParenthesis: ( @115
                      rightParenthesis: ) @116
                    element: package:test/a.dart::@class::A::@constructor::new
                type: int
                shouldUseTypeForInitializerInference: true
            accessors
              synthetic get foo @-1
                returnType: int
              synthetic get bar @-1
                returnType: int
''');
  }

  test_codeOptimizer_metadata_class_getter() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType("""
  @{{package:test/a.dart@A}}()
  int get foo => 0;""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  @prefix0.A()
  int get foo => 0;
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            fields
              synthetic foo @-1
                type: int
            accessors
              get foo @128
                metadata
                  Annotation
                    atSign: @ @105
                    name: PrefixedIdentifier
                      prefix: SimpleIdentifier
                        token: prefix0 @106
                        staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                        staticType: null
                      period: . @113
                      identifier: SimpleIdentifier
                        token: A @114
                        staticElement: package:test/a.dart::@class::A
                        staticType: null
                      staticElement: package:test/a.dart::@class::A
                      staticType: null
                    arguments: ArgumentList
                      leftParenthesis: ( @115
                      rightParenthesis: ) @116
                    element: package:test/a.dart::@class::A::@constructor::new
                returnType: int
''');
  }

  test_codeOptimizer_metadata_class_method() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType("""
  @{{package:test/a.dart@A}}()
  void foo() {}""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  @prefix0.A()
  void foo() {}
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            methods
              foo @125
                metadata
                  Annotation
                    atSign: @ @105
                    name: PrefixedIdentifier
                      prefix: SimpleIdentifier
                        token: prefix0 @106
                        staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                        staticType: null
                      period: . @113
                      identifier: SimpleIdentifier
                        token: A @114
                        staticElement: package:test/a.dart::@class::A
                        staticType: null
                      staticElement: package:test/a.dart::@class::A
                      staticType: null
                    arguments: ArgumentList
                      leftParenthesis: ( @115
                      rightParenthesis: ) @116
                    element: package:test/a.dart::@class::A::@constructor::new
                returnType: void
''');
  }

  test_codeOptimizer_metadata_class_setter() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType("""
  @{{package:test/a.dart@A}}()
  set foo(int _) {}""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class B {
  @prefix0.A()
  set foo(int _) {}
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class B @99
            augmentationTarget: self::@class::B
            fields
              synthetic foo @-1
                type: int
            accessors
              set foo= @124
                metadata
                  Annotation
                    atSign: @ @105
                    name: PrefixedIdentifier
                      prefix: SimpleIdentifier
                        token: prefix0 @106
                        staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                        staticType: null
                      period: . @113
                      identifier: SimpleIdentifier
                        token: A @114
                        staticElement: package:test/a.dart::@class::A
                        staticType: null
                      staticElement: package:test/a.dart::@class::A
                      staticType: null
                    arguments: ArgumentList
                      leftParenthesis: ( @115
                      rightParenthesis: ) @116
                    element: package:test/a.dart::@class::A::@constructor::new
                parameters
                  requiredPositional _ @132
                    type: int
                returnType: void
''');
  }

  test_codeOptimizer_metadata_unit_function() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInLibrary("""
@{{package:test/a.dart@A}}()
void foo() {}""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.A()
void foo() {}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        functions
          foo @103
            metadata
              Annotation
                atSign: @ @85
                name: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @86
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @93
                  identifier: SimpleIdentifier
                    token: A @94
                    staticElement: package:test/a.dart::@class::A
                    staticType: null
                  staticElement: package:test/a.dart::@class::A
                  staticType: null
                arguments: ArgumentList
                  leftParenthesis: ( @95
                  rightParenthesis: ) @96
                element: package:test/a.dart::@class::A::@constructor::new
            returnType: void
''');
  }

  test_codeOptimizer_metadata_unit_function_optionalPositional_defaultValue() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInLibrary('void foo([x = {{package:test/a.dart@a}}]) {}')
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

void foo([x = prefix0.a]) {}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        functions
          foo @90
            parameters
              optionalPositional default x @95
                type: dynamic
                constantInitializer
                  PrefixedIdentifier
                    prefix: SimpleIdentifier
                      token: prefix0 @99
                      staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                      staticType: null
                    period: . @106
                    identifier: SimpleIdentifier
                      token: a @107
                      staticElement: package:test/a.dart::@getter::a
                      staticType: int
                    staticElement: package:test/a.dart::@getter::a
                    staticType: int
            returnType: void
''');
  }

  test_codeOptimizer_metadata_unit_getter() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInLibrary("""
@{{package:test/a.dart@A}}()
int get foo => 0;""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.A()
int get foo => 0;
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        topLevelVariables
          synthetic static foo @-1
            type: int
        accessors
          static get foo @106
            metadata
              Annotation
                atSign: @ @85
                name: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @86
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @93
                  identifier: SimpleIdentifier
                    token: A @94
                    staticElement: package:test/a.dart::@class::A
                    staticType: null
                  staticElement: package:test/a.dart::@class::A
                  staticType: null
                arguments: ArgumentList
                  leftParenthesis: ( @95
                  rightParenthesis: ) @96
                element: package:test/a.dart::@class::A::@constructor::new
            returnType: int
''');
  }

  test_codeOptimizer_metadata_unit_setter() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInLibrary("""
@{{package:test/a.dart@A}}()
set foo(int _) {}""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.A()
set foo(int _) {}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        topLevelVariables
          synthetic static foo @-1
            type: int
        accessors
          static set foo= @102
            metadata
              Annotation
                atSign: @ @85
                name: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @86
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @93
                  identifier: SimpleIdentifier
                    token: A @94
                    staticElement: package:test/a.dart::@class::A
                    staticType: null
                  staticElement: package:test/a.dart::@class::A
                  staticType: null
                arguments: ArgumentList
                  leftParenthesis: ( @95
                  rightParenthesis: ) @96
                element: package:test/a.dart::@class::A::@constructor::new
            parameters
              requiredPositional _ @110
                type: int
            returnType: void
''');
  }

  test_codeOptimizer_metadata_unit_setter_requiredPositional_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInLibrary('set foo(@{{package:test/a.dart@a}} x) {}')
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

set foo(@prefix0.a x) {}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        topLevelVariables
          synthetic static foo @-1
            type: dynamic
        accessors
          static set foo= @89
            parameters
              requiredPositional x @104
                type: dynamic
                metadata
                  Annotation
                    atSign: @ @93
                    name: PrefixedIdentifier
                      prefix: SimpleIdentifier
                        token: prefix0 @94
                        staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                        staticType: null
                      period: . @101
                      identifier: SimpleIdentifier
                        token: a @102
                        staticElement: package:test/a.dart::@getter::a
                        staticType: null
                      staticElement: package:test/a.dart::@getter::a
                      staticType: null
                    element: package:test/a.dart::@getter::a
            returnType: void
''');
  }

  test_codeOptimizer_metadata_unit_variable() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInLibrary("""
@{{package:test/a.dart@A}}()
final foo = 0;""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.A()
final foo = 0;
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        topLevelVariables
          static final foo @104
            metadata
              Annotation
                atSign: @ @85
                name: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @86
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @93
                  identifier: SimpleIdentifier
                    token: A @94
                    staticElement: package:test/a.dart::@class::A
                    staticType: null
                  staticElement: package:test/a.dart::@class::A
                  staticType: null
                arguments: ArgumentList
                  leftParenthesis: ( @95
                  rightParenthesis: ) @96
                element: package:test/a.dart::@class::A::@constructor::new
            type: int
            shouldUseTypeForInitializerInference: false
        accessors
          synthetic static get foo @-1
            returnType: int
''');
  }

  test_codeOptimizer_metadata_unit_variable2() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInLibrary("""
@{{package:test/a.dart@A}}()
final foo = 0, bar = 1;""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.A()
final foo = 0, bar = 1;
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        topLevelVariables
          static final foo @104
            metadata
              Annotation
                atSign: @ @85
                name: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @86
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @93
                  identifier: SimpleIdentifier
                    token: A @94
                    staticElement: package:test/a.dart::@class::A
                    staticType: null
                  staticElement: package:test/a.dart::@class::A
                  staticType: null
                arguments: ArgumentList
                  leftParenthesis: ( @95
                  rightParenthesis: ) @96
                element: package:test/a.dart::@class::A::@constructor::new
            type: int
            shouldUseTypeForInitializerInference: false
          static final bar @113
            metadata
              Annotation
                atSign: @ @85
                name: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @86
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @93
                  identifier: SimpleIdentifier
                    token: A @94
                    staticElement: package:test/a.dart::@class::A
                    staticType: null
                  staticElement: package:test/a.dart::@class::A
                  staticType: null
                arguments: ArgumentList
                  leftParenthesis: ( @95
                  rightParenthesis: ) @96
                element: package:test/a.dart::@class::A::@constructor::new
            type: int
            shouldUseTypeForInitializerInference: false
        accessors
          synthetic static get foo @-1
            returnType: int
          synthetic static get bar @-1
            returnType: int
''');
  }

  test_codeOptimizer_metadata_uses_function() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A(Object _);
}

void foo() {}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareTypesPhase('C', """
@{{package:test/a.dart@A}}({{package:test/a.dart@foo}})
class C {}""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.A(prefix0.foo)
class C {}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          class C @115
            metadata
              Annotation
                atSign: @ @85
                name: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @86
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @93
                  identifier: SimpleIdentifier
                    token: A @94
                    staticElement: package:test/a.dart::@class::A
                    staticType: null
                  staticElement: package:test/a.dart::@class::A
                  staticType: null
                arguments: ArgumentList
                  leftParenthesis: ( @95
                  arguments
                    PrefixedIdentifier
                      prefix: SimpleIdentifier
                        token: prefix0 @96
                        staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                        staticType: null
                      period: . @103
                      identifier: SimpleIdentifier
                        token: foo @104
                        staticElement: package:test/a.dart::@function::foo
                        staticType: void Function()
                      staticElement: package:test/a.dart::@function::foo
                      staticType: void Function()
                  rightParenthesis: ) @107
                element: package:test/a.dart::@class::A::@constructor::new
''');
  }

  test_codeOptimizer_metadata_uses_namedConstructor() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A.named();
}

class X<T> {}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareTypesPhase('C', """
@{{package:test/a.dart@A}}.named()
class C {}""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.A.named()
class C {}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          class C @110
            metadata
              Annotation
                atSign: @ @85
                name: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @86
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @93
                  identifier: SimpleIdentifier
                    token: A @94
                    staticElement: package:test/a.dart::@class::A
                    staticType: null
                  staticElement: package:test/a.dart::@class::A
                  staticType: null
                period: . @95
                constructorName: SimpleIdentifier
                  token: named @96
                  staticElement: package:test/a.dart::@class::A::@constructor::named
                  staticType: null
                arguments: ArgumentList
                  leftParenthesis: ( @101
                  rightParenthesis: ) @102
                element: package:test/a.dart::@class::A::@constructor::named
''');
  }

  test_codeOptimizer_metadata_uses_namedType() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A(Object _);
}

class X<T> {}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareTypesPhase('C', """
@{{package:test/a.dart@A}}({{package:test/a.dart@X}}<void>)
class C {}""")
class B {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.A(prefix0.X<void>)
class C {}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          class C @119
            metadata
              Annotation
                atSign: @ @85
                name: PrefixedIdentifier
                  prefix: SimpleIdentifier
                    token: prefix0 @86
                    staticElement: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                    staticType: null
                  period: . @93
                  identifier: SimpleIdentifier
                    token: A @94
                    staticElement: package:test/a.dart::@class::A
                    staticType: null
                  staticElement: package:test/a.dart::@class::A
                  staticType: null
                arguments: ArgumentList
                  leftParenthesis: ( @95
                  arguments
                    TypeLiteral
                      type: NamedType
                        importPrefix: ImportPrefixReference
                          name: prefix0 @96
                          period: . @103
                          element: self::@augmentation::package:test/test.macro.dart::@prefix::prefix0
                        name: X @104
                        typeArguments: TypeArgumentList
                          leftBracket: < @105
                          arguments
                            NamedType
                              name: void @106
                              element: <null>
                              type: void
                          rightBracket: > @110
                        element: package:test/a.dart::@class::X
                        type: X<void>
                      staticType: Type
                  rightParenthesis: ) @111
                element: package:test/a.dart::@class::A::@constructor::new
''');
  }

  test_codeOptimizer_namedType_notUniqueImport() async {
    newFile('$testPackageLibPath/a.dart', r'''
class X {}
''');

    newFile('$testPackageLibPath/b.dart', r'''
class X {}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';
import 'b.dart';

@DeclareInLibrary('void foo({{package:test/a.dart@X}} x1, {{package:test/b.dart@X}} x2) {}')
class A {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
    package:test/b.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;
import 'package:test/b.dart' as prefix1;

void foo(prefix0.X x1, prefix1.X x2) {}
---
      imports
        package:test/a.dart as prefix0 @75
        package:test/b.dart as prefix1 @116
      definingUnit
        functions
          foo @131
            parameters
              requiredPositional x1 @145
                type: X
              requiredPositional x2 @159
                type: X
            returnType: void
''');
  }

  test_codeOptimizer_namedType_shadowedLocally() async {
    newFile('$testPackageLibPath/a.dart', r'''
class X {}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInLibrary('void foo({{package:test/a.dart@X}} x) {}')
class A {}

class X {}
''');

    configuration.forCodeOptimizer();
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

void foo(prefix0.X x) {}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        functions
          foo @90
            parameters
              requiredPositional x @104
                type: X
            returnType: void
''');
  }

  test_libraryCycle_class_constructor_add() async {
    // Checks https://github.com/dart-lang/sdk/issues/55362
    newFile('$testPackageLibPath/a.dart', r'''
import 'append.dart';

// Just to make it a library cycle.
import 'test.dart';

@DeclareInType('  A();')
class A {}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType('  B();')
class B {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/append.dart
    package:test/a.dart
  definingUnit
    reference: self
    classes
      class B @71
        reference: self::@class::B
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::B
        augmented
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

augment class B {
  B();
}
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class B @57
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::B
            augmentationTarget: self::@class::B
''');
  }

  test_unit_function_add() async {
    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareInLibrary('void foo() {}')
class A {}
''');

    configuration
      ..withConstructors = false
      ..withExportScope = true
      ..withMetadata = false
      ..withPropertyLinking = true
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/append.dart
  definingUnit
    reference: self
    classes
      class A @64
        reference: self::@class::A
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

void foo() {}
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        functions
          foo @48
            reference: self::@augmentation::package:test/test.macro.dart::@function::foo
            returnType: void
  exportedReferences
    declared self::@augmentation::package:test/test.macro.dart::@function::foo
    declared self::@class::A
  exportNamespace
    A: self::@class::A
    foo: self::@augmentation::package:test/test.macro.dart::@function::foo
''');
  }

  test_unit_variable_add() async {
    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareInLibrary('final x = 42;')
class A {}
''');

    configuration
      ..withConstructors = false
      ..withExportScope = true
      ..withMetadata = false
      ..withPropertyLinking = true
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/append.dart
  definingUnit
    reference: self
    classes
      class A @64
        reference: self::@class::A
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

final x = 42;
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        topLevelVariables
          static final x @49
            reference: self::@augmentation::package:test/test.macro.dart::@topLevelVariable::x
            type: int
            shouldUseTypeForInitializerInference: false
            id: variable_0
            getter: getter_0
        accessors
          synthetic static get x @-1
            reference: self::@augmentation::package:test/test.macro.dart::@accessor::x
            returnType: int
            id: getter_0
            variable: variable_0
  exportedReferences
    declared self::@augmentation::package:test/test.macro.dart::@accessor::x
    declared self::@class::A
  exportNamespace
    A: self::@class::A
    x: self::@augmentation::package:test/test.macro.dart::@accessor::x
''');
  }
}

@reflectiveTest
class MacroDeclarationsTest_fromBytes extends MacroDeclarationsTest {
  @override
  bool get keepLinkingLibraries => false;
}

@reflectiveTest
class MacroDeclarationsTest_keepLinking extends MacroDeclarationsTest {
  @override
  bool get keepLinkingLibraries => true;
}

abstract class MacroDefinitionTest extends MacroElementsBaseTest {
  test_class_addConstructor_augmentConstructor() async {
    newFile(
      '$testPackageLibPath/a.dart',
      _getMacroCode('add_augment_declaration.dart'),
    );

    var library = await buildLibrary(r'''
import 'a.dart';

@AddConstructor()
class A {}
''');

    configuration
      ..withMetadata = false
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/a.dart
  definingUnit
    reference: self
    classes
      class A @42
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        augmented
          constructors
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructorAugmentation::named
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class A {
  @prefix0.AugmentConstructor()
  A.named();
  augment A.named() { print(42); }
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @99
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            constructors
              named @139
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructor::named
                periodOffset: 138
                nameEnd: 144
                augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructorAugmentation::named
              augment named @160
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructorAugmentation::named
                periodOffset: 159
                nameEnd: 165
                augmentationTarget: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructor::named
''');
  }

  test_class_addField_augmentField() async {
    newFile(
      '$testPackageLibPath/a.dart',
      _getMacroCode('add_augment_declaration.dart'),
    );

    var library = await buildLibrary(r'''
import 'a.dart';

@AddField()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false
      ..withPropertyLinking = true
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/a.dart
  definingUnit
    reference: self
    classes
      class A @36
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        augmented
          fields
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@fieldAugmentation::foo
          accessors
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@getter::foo
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@setter::foo
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;
import 'dart:core' as prefix1;

augment class A {
  @prefix0.AugmentField()
  prefix1.int foo;
  augment prefix1.int foo = 42;
}
---
      imports
        package:test/a.dart as prefix0 @75
        dart:core as prefix1 @106
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @130
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            fields
              foo @174
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@field::foo
                type: int
                id: field_0
                getter: getter_0
                setter: setter_0
                augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@fieldAugmentation::foo
              augment foo @201
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@fieldAugmentation::foo
                type: int
                shouldUseTypeForInitializerInference: true
                id: field_1
                augmentationTarget: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@field::foo
            accessors
              synthetic get foo @-1
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@getter::foo
                returnType: int
                id: getter_0
                variable: field_0
              synthetic set foo= @-1
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@setter::foo
                parameters
                  requiredPositional _foo @-1
                    type: int
                returnType: void
                id: setter_0
                variable: field_0
''');
  }

  test_class_addGetter_augmentGetter() async {
    newFile(
      '$testPackageLibPath/a.dart',
      _getMacroCode('add_augment_declaration.dart'),
    );

    var library = await buildLibrary(r'''
import 'a.dart';

@AddGetter()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false
      ..withPropertyLinking = true
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/a.dart
  definingUnit
    reference: self
    classes
      class A @37
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        augmented
          fields
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@field::foo
          accessors
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@getterAugmentation::foo
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;
import 'dart:core' as prefix1;

augment class A {
  @prefix0.AugmentGetter()
  external prefix1.int get foo;
  augment prefix1.int get foo => 42;
}
---
      imports
        package:test/a.dart as prefix0 @75
        dart:core as prefix1 @106
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @130
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            fields
              synthetic foo @-1
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@field::foo
                type: int
                id: field_0
                getter: getter_0
            accessors
              external get foo @188
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@getter::foo
                returnType: int
                id: getter_0
                variable: field_0
                augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@getterAugmentation::foo
              augment get foo @219
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@getterAugmentation::foo
                returnType: int
                id: getter_1
                variable: field_0
                augmentationTarget: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@getter::foo
''');
  }

  test_class_addMethod_augmentMethod() async {
    newFile(
      '$testPackageLibPath/a.dart',
      _getMacroCode('add_augment_declaration.dart'),
    );

    var library = await buildLibrary(r'''
import 'a.dart';

@AddMethod()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/a.dart
  definingUnit
    reference: self
    classes
      class A @37
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        augmented
          methods
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@methodAugmentation::foo
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;
import 'dart:core' as prefix1;

augment class A {
  @prefix0.AugmentMethod()
  external prefix1.int foo();
  augment prefix1.int foo() => 42;
}
---
      imports
        package:test/a.dart as prefix0 @75
        dart:core as prefix1 @106
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @130
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            methods
              external foo @184
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@method::foo
                returnType: int
                augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@methodAugmentation::foo
              augment foo @213
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@methodAugmentation::foo
                returnType: int
                augmentationTarget: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@method::foo
''');
  }

  test_class_addSetter_augmentSetter() async {
    newFile(
      '$testPackageLibPath/a.dart',
      _getMacroCode('add_augment_declaration.dart'),
    );

    var library = await buildLibrary(r'''
import 'a.dart';

@AddSetter()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false
      ..withPropertyLinking = true
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/a.dart
  definingUnit
    reference: self
    classes
      class A @37
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        augmented
          fields
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@field::foo
          accessors
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@setterAugmentation::foo
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;
import 'dart:core' as prefix1;

augment class A {
  @prefix0.AugmentSetter()
  external void set foo(prefix1.int value);
  augment void set foo(prefix1.int value, ) { print(42); }
}
---
      imports
        package:test/a.dart as prefix0 @75
        dart:core as prefix1 @106
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @130
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            fields
              synthetic foo @-1
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@field::foo
                type: int
                id: field_0
                setter: setter_0
            accessors
              external set foo= @181
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@setter::foo
                parameters
                  requiredPositional value @197
                    type: int
                returnType: void
                id: setter_0
                variable: field_0
                augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@setterAugmentation::foo
              augment set foo= @224
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@setterAugmentation::foo
                parameters
                  requiredPositional value @240
                    type: int
                returnType: void
                id: setter_1
                variable: field_0
                augmentationTarget: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@setter::foo
''');
  }
}

@reflectiveTest
class MacroDefinitionTest_fromBytes extends MacroDefinitionTest {
  @override
  bool get keepLinkingLibraries => false;
}

@reflectiveTest
class MacroDefinitionTest_keepLinking extends MacroDefinitionTest {
  @override
  bool get keepLinkingLibraries => true;
}

abstract class MacroElementsBaseTest extends ElementsBaseTest {
  /// We decided that we want to fail, and want to print the library.
  void failWithLibraryText(LibraryElementImpl library) {
    // While developing, we hit unimplemented branches.
    // It is useful to see where, so include stack traces.
    configuration.withMacroStackTraces = true;

    var text = getLibraryText(
      library: library,
      configuration: configuration,
    );
    print('------------------------');
    print('$text------------------------');
    fail('The library text above should have details.');
  }

  @override
  Future<void> setUp() async {
    super.setUp();

    writeTestPackageConfig(
      PackageConfigFileBuilder(),
      macrosEnvironment: MacrosEnvironment.instance,
    );

    newFile(
      '$testPackageLibPath/append.dart',
      _getMacroCode('append.dart'),
    );
  }

  /// Adds `a.dart` with the content from `single/` directory.
  void _addSingleMacro(String fileName) {
    var code = _getMacroCode('single/$fileName');
    newFile('$testPackageLibPath/a.dart', code);
  }

  /// Matches [library]'s generated code against `=> r'''(.+)''';` pattern,
  /// and verifies that the extracted content is [expected].
  void _assertDefinitionsPhaseText(
    LibraryElementImpl library,
    String expected,
  ) {
    if (library.allMacroDiagnostics.isNotEmpty) {
      failWithLibraryText(library);
    }

    var generated = _getMacroGeneratedCode(library);

    var regExp = RegExp(r'=> r"""(.+)""";', dotAll: true);
    var match = regExp.firstMatch(generated);
    var actual = match?.group(1);

    if (actual == null) {
      print('-------- Generated --------');
      print('$generated---------------------------');
      fail('No introspection result.');
    }

    if (actual != expected) {
      print('-------- Actual --------');
      print('$actual------------------------');
      NodeTextExpectationsCollector.add(actual);
    }
    expect(actual, expected);
  }

  /// Runs the definitions phase macro that introspects the declaration in
  /// the library [uriStr], with the [name].
  Future<void> _assertIntrospectDefinitionText(
    String leadCode,
    String expected, {
    required String name,
    required String uriStr,
    required bool withUnnamedConstructor,
  }) async {
    var library = await buildLibrary('''
$leadCode

@IntrospectDeclaration(
  uriStr: '$uriStr',
  name: '$name',
  withUnnamedConstructor: $withUnnamedConstructor,
)
void _starter() {}
''');

    _assertDefinitionsPhaseText(library, expected);
  }

  /// Verifies the code of the macro generated augmentation.
  void _assertMacroCode(LibraryElementImpl library, String expected) {
    var actual = _getMacroGeneratedCode(library);
    if (actual != expected) {
      print('-------- Actual --------');
      print('$actual------------------------');
      NodeTextExpectationsCollector.add(actual);
    }
    expect(actual, expected);
  }

  String _getMacroCode(String relativePath) {
    var code = MacrosEnvironment.instance.packageAnalyzerFolder
        .getChildAssumingFile('test/src/summary/macro/$relativePath')
        .readAsStringSync();
    return code.replaceAll('/*macro*/', 'macro');
  }

  String _getMacroGeneratedCode(LibraryElementImpl library) {
    if (library.allMacroDiagnostics.isNotEmpty) {
      failWithLibraryText(library);
    }

    return library.augmentations.single.macroGenerated!.code;
  }
}

abstract class MacroElementsTest extends MacroElementsBaseTest {
  @override
  bool get retainDataForTesting => true;

  @FailingTest(
    issue: 'https://github.com/dart-lang/sdk/issues/55931',
    reason: r'''
Here we apply `SetExtendsType` first, so `augment class B` is first.
Then we apply `DeclareType`, so `class C @113` is next.
But the actual merged code has the different order.
Note, that the code below has the _expected_ merged code.
''',
  )
  test_addClass_extendsTypeOther() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {}

@DeclareType('C', 'class C {}')
@SetExtendsType('{{package:test/test.dart@A}}', [])
class B {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
      class B @125
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::B
        supertype: A
        augmented
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/test.dart' as prefix0;

augment class B extends prefix0.A {
}
class C {}
---
      imports
        package:test/test.dart as prefix0 @78
      definingUnit
        classes
          augment class B @94
            augmentationTarget: self::@class::B
          class C @113
''');
  }

  test_disable_declarationsPhase() async {
    var library = await buildLibrary(r'''
// @dart = 3.2
import 'append.dart';

@DeclareInType('  void foo() {}')
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @78
''');
  }

  test_disable_definitionsPhase() async {
    var library = await buildLibrary(r'''
// @dart = 3.2
import 'append.dart';

class A {
  @AugmentDefinition('{ print(0); }')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @44
        methods
          foo @93
            returnType: void
''');
  }

  test_disable_typesPhase() async {
    var library = await buildLibrary(r'''
// @dart = 3.2
import 'append.dart';

@DeclareType('B', 'class B {}')
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @76
''');
  }

  test_exportedMacro() async {
    newFile('$testPackageLibPath/a.dart', r'''
export 'append.dart';
''');

    var library = await buildLibrary(r'''
import 'a.dart';

@DeclareType('B', 'class B {}')
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/a.dart
  definingUnit
    classes
      class A @56
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class B {}
---
      definingUnit
        classes
          class B @49
''');
  }

  test_macroApplicationErrors_typesPhase_compileTimeError() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'package:macros/macros.dart';

macro class MyMacro implements ClassTypesMacro {
  const MyMacro();

  buildTypesForClass(clazz, builder) {
    unresolved;
  }
}
''');

    var library = await buildLibrary(r'''
import 'a.dart';

@MyMacro()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false
      ..macroDiagnosticMessagePatterns = [
        'Macro application failed due to a bug in the macro.',
        'package:test/a.dart',
        'MyMacro',
        'unresolved',
      ];
    checkElementText(library, r'''
library
  imports
    package:test/a.dart
  definingUnit
    classes
      class A @35
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              contains
                Macro application failed due to a bug in the macro.
              target: ApplicationMacroDiagnosticTarget
                annotationIndex: 0
            contextMessages
              MacroDiagnosticMessage
                contains
                  package:test/a.dart
                  MyMacro
                  unresolved
                target: ApplicationMacroDiagnosticTarget
                  annotationIndex: 0
            severity: error
            correctionMessage: Try reporting the failure to the macro author.
''');
  }

  test_macroDiagnostics_invalidTarget_wantsClassOrMixin_hasFunction() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@TargetClassOrMixinMacro()
void f() {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    functions
      f @59
        returnType: void
        macroDiagnostics
          InvalidMacroTargetDiagnostic
            annotationIndex: 0
            supportedKinds
              classType
              mixinType
''');
  }

  test_macroDiagnostics_invalidTarget_wantsClassOrMixin_hasLibrary() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
@TargetClassOrMixinMacro()
library;

import 'diagnostic.dart';
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
  macroDiagnostics
    InvalidMacroTargetDiagnostic
      annotationIndex: 0
      supportedKinds
        classType
        mixinType
''');
  }

  test_macroDiagnostics_report_atAnnotation_constructor() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A();
}
''');

    var library = await buildLibrary(r'''
import 'diagnostic.dart';
import 'a.dart';

@ReportAtTargetAnnotation(1)
@A()
class X {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
    package:test/a.dart
  definingUnit
    classes
      class X @84
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: ElementAnnotationMacroDiagnosticTarget
                element: self::@class::X
                annotationIndex: 1
            severity: warning
            correctionMessage: Correction message
''');
  }

  test_macroDiagnostics_report_atAnnotation_identifier() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    var library = await buildLibrary(r'''
import 'diagnostic.dart';
import 'a.dart';

@ReportAtTargetAnnotation(1)
@a
class X {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
    package:test/a.dart
  definingUnit
    classes
      class X @82
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: ElementAnnotationMacroDiagnosticTarget
                element: self::@class::X
                annotationIndex: 1
            severity: warning
            correctionMessage: Correction message
''');
  }

  test_macroDiagnostics_report_atDeclaration_class() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTargetDeclaration()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @62
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: ElementMacroDiagnosticTarget
                element: self::@class::A
            severity: warning
            correctionMessage: Correction message
''');
  }

  test_macroDiagnostics_report_atDeclaration_class_method_typeParameter() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ReportAtDeclaration([
    'typeParameter 0',
  ])
  void foo<T>() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        methods
          foo @97
            typeParameters
              covariant T @101
                defaultType: dynamic
            returnType: void
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Reported message
                  target: ElementMacroDiagnosticTarget
                    element: T@101
                severity: warning
''');
  }

  test_macroDiagnostics_report_atDeclaration_class_typeParameter() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtDeclaration([
  'typeParameter 1',
])
class A<T, U, V> {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @80
        typeParameters
          covariant T @82
            defaultType: dynamic
          covariant U @85
            defaultType: dynamic
          covariant V @88
            defaultType: dynamic
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: ElementMacroDiagnosticTarget
                element: U@85
            severity: warning
''');
  }

  test_macroDiagnostics_report_atDeclaration_constructor() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ReportAtTargetDeclaration()
  A();
}
''');

    configuration.withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        constructors
          @70
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Reported message
                  target: ElementMacroDiagnosticTarget
                    element: self::@class::A::@constructor::new
                severity: warning
                correctionMessage: Correction message
''');
  }

  test_macroDiagnostics_report_atDeclaration_field() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ReportAtTargetDeclaration()
  final int foo = 0;
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        fields
          final foo @80
            type: int
            shouldUseTypeForInitializerInference: true
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Reported message
                  target: ElementMacroDiagnosticTarget
                    element: self::@class::A::@field::foo
                severity: warning
                correctionMessage: Correction message
        accessors
          synthetic get foo @-1
            returnType: int
''');
  }

  test_macroDiagnostics_report_atDeclaration_function_typeParameter() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtDeclaration([
  'typeParameter 0',
])
void foo<T>() {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    functions
      foo @79
        typeParameters
          covariant T @83
            defaultType: dynamic
        returnType: void
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: ElementMacroDiagnosticTarget
                element: T@83
            severity: warning
''');
  }

  test_macroDiagnostics_report_atDeclaration_method() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ReportAtTargetDeclaration()
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        methods
          foo @75
            returnType: void
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Reported message
                  target: ElementMacroDiagnosticTarget
                    element: self::@class::A::@method::foo
                severity: warning
                correctionMessage: Correction message
''');
  }

  test_macroDiagnostics_report_atDeclaration_mixin() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTargetDeclaration()
mixin A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    mixins
      mixin A @62
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: ElementMacroDiagnosticTarget
                element: self::@mixin::A
            severity: warning
            correctionMessage: Correction message
        superclassConstraints
          Object
''');
  }

  test_macroDiagnostics_report_atDeclaration_mixin_typeParameter() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtDeclaration([
  'typeParameter 0',
])
mixin A<T> {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    mixins
      mixin A @80
        typeParameters
          covariant T @82
            defaultType: dynamic
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: ElementMacroDiagnosticTarget
                element: T@82
            severity: warning
        superclassConstraints
          Object
''');
  }

  test_macroDiagnostics_report_atDeclaration_typeAlias_typeParameter() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtDeclaration([
  'typeParameter 0',
])
typedef A<T> = List<T>;
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    typeAliases
      A @82
        typeParameters
          covariant T @84
            defaultType: dynamic
        aliasedType: List<T>
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: ElementMacroDiagnosticTarget
                element: T@84
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTarget_method() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtFirstMethod()
class A {
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @56
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: ElementMacroDiagnosticTarget
                element: self::@class::A::@method::foo
            severity: warning
        methods
          foo @67
            returnType: void
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_class_extends() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'superclass',
])
class A extends Object {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @78
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@class::A
                ExtendsClauseTypeLocation
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_field_type() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ReportAtTypeAnnotation([
    'variableType',
  ])
  final int foo = 0;
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        fields
          final foo @102
            type: int
            shouldUseTypeForInitializerInference: true
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Reported message
                  target: TypeAnnotationMacroDiagnosticTarget
                    ElementTypeLocation
                      element: self::@class::A::@field::foo
                    VariableTypeLocation
                severity: warning
        accessors
          synthetic get foo @-1
            returnType: int
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_function_formalParameter_named() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'namedFormalParameterType 0',
])
void foo(int a, {String? b, bool? c}) {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    functions
      foo @93
        parameters
          requiredPositional a @101
            type: int
          optionalNamed default b @113
            type: String?
          optionalNamed default c @122
            type: bool?
        returnType: void
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@function::foo
                FormalParameterTypeLocation
                  index: 1
                VariableTypeLocation
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_function_formalParameter_positional() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'positionalFormalParameterType 1',
])
void foo(int a, String b) {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    functions
      foo @98
        parameters
          requiredPositional a @106
            type: int
          requiredPositional b @116
            type: String
        returnType: void
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@function::foo
                FormalParameterTypeLocation
                  index: 1
                VariableTypeLocation
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_function_returnType() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'returnType',
])
int foo() => 0;
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    functions
      foo @76
        returnType: int
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@function::foo
                ReturnTypeLocation
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_functionType_formalParameter_named() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'returnType',
  'namedFormalParameterType 1',
])
int Function(bool a, {int b, String c}) foo() => throw 0;
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    functions
      foo @144
        returnType: int Function(bool, {int b, String c})
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@function::foo
                ReturnTypeLocation
                FormalParameterTypeLocation
                  index: 2
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_functionType_formalParameter_positional() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'returnType',
  'positionalFormalParameterType 1',
])
int Function(int a, String b) foo() => throw 0;
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    functions
      foo @139
        returnType: int Function(int, String)
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@function::foo
                ReturnTypeLocation
                FormalParameterTypeLocation
                  index: 1
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_functionType_returnType() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'returnType',
  'returnType',
])
int Function() foo() => throw 0;
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    functions
      foo @103
        returnType: int Function()
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@function::foo
                ReturnTypeLocation
                ReturnTypeLocation
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_kind_functionType() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'returnType',
])
void Function() foo() => throw 0;
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    functions
      foo @88
        returnType: void Function()
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@function::foo
                ReturnTypeLocation
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_kind_omittedType_fieldType() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ReportAtTypeAnnotation([
    'variableType',
  ])
  final foo = 0;
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        fields
          final foo @98
            type: int
            shouldUseTypeForInitializerInference: false
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Reported message
                  target: TypeAnnotationMacroDiagnosticTarget
                    ElementTypeLocation
                      element: self::@class::A::@field::foo
                    VariableTypeLocation
                severity: warning
        accessors
          synthetic get foo @-1
            returnType: int
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_kind_omittedType_formalParameterType() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'positionalFormalParameterType 0',
])
void foo(a) {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    functions
      foo @98
        parameters
          requiredPositional a @102
            type: dynamic
        returnType: void
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@function::foo
                FormalParameterTypeLocation
                  index: 0
                VariableTypeLocation
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_kind_omittedType_functionReturnType() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'returnType',
])
foo() => throw 0;
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    functions
      foo @72
        returnType: dynamic
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@function::foo
                ReturnTypeLocation
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_kind_omittedType_methodReturnType() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ReportAtTypeAnnotation([
    'returnType',
  ])
  foo() => throw 0;
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        methods
          foo @90
            returnType: dynamic
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Reported message
                  target: TypeAnnotationMacroDiagnosticTarget
                    ElementTypeLocation
                      element: self::@class::A::@method::foo
                    ReturnTypeLocation
                severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_kind_omittedType_topLevelVariableType() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'variableType',
])
final foo = 0;
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    topLevelVariables
      static final foo @80
        type: int
        shouldUseTypeForInitializerInference: false
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@variable::foo
                VariableTypeLocation
            severity: warning
    accessors
      synthetic static get foo @-1
        returnType: int
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_kind_recordType() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'returnType',
])
(int, String) foo() => throw 0;
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    functions
      foo @86
        returnType: (int, String)
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@function::foo
                ReturnTypeLocation
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_kind_typedef_namedType() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

typedef A = List<int>;

@ReportAtTypeAnnotation([
  'returnType',
])
A foo() => throw 0;
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    typeAliases
      A @35
        aliasedType: List<int>
    functions
      foo @98
        returnType: List<int>
          alias: self::@typeAlias::A
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@function::foo
                ReturnTypeLocation
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_method_formalParameter_positional() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ReportAtTypeAnnotation([
    'positionalFormalParameterType 1',
  ])
  void foo(int a, String b) {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        methods
          foo @116
            parameters
              requiredPositional a @124
                type: int
              requiredPositional b @134
                type: String
            returnType: void
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Reported message
                  target: TypeAnnotationMacroDiagnosticTarget
                    ElementTypeLocation
                      element: self::@class::A::@method::foo
                    FormalParameterTypeLocation
                      index: 1
                    VariableTypeLocation
                severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_method_returnType() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ReportAtTypeAnnotation([
    'returnType',
  ])
  int foo() => 0;
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        methods
          foo @94
            returnType: int
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Reported message
                  target: TypeAnnotationMacroDiagnosticTarget
                    ElementTypeLocation
                      element: self::@class::A::@method::foo
                    ReturnTypeLocation
                severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_namedTypeArgument() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'returnType',
  'namedTypeArgument 1',
])
Map<int, String> foo() {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    functions
      foo @114
        returnType: Map<int, String>
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@function::foo
                ReturnTypeLocation
                ListIndexTypeLocation
                  index: 1
            severity: warning
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_record_namedField() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ReportAtTypeAnnotation([
    'variableType',
    'namedField 1',
  ])
  final (bool, {int a, String b})? foo = null;
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        fields
          final foo @145
            type: (bool, {int a, String b})?
            shouldUseTypeForInitializerInference: true
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Reported message
                  target: TypeAnnotationMacroDiagnosticTarget
                    ElementTypeLocation
                      element: self::@class::A::@field::foo
                    VariableTypeLocation
                    RecordNamedFieldTypeLocation
                      index: 1
                severity: warning
        accessors
          synthetic get foo @-1
            returnType: (bool, {int a, String b})?
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_record_positionalField() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ReportAtTypeAnnotation([
    'variableType',
    'positionalField 1',
  ])
  final (int, String)? foo = null;
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        fields
          final foo @138
            type: (int, String)?
            shouldUseTypeForInitializerInference: true
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Reported message
                  target: TypeAnnotationMacroDiagnosticTarget
                    ElementTypeLocation
                      element: self::@class::A::@field::foo
                    VariableTypeLocation
                    RecordPositionalFieldTypeLocation
                      index: 1
                severity: warning
        accessors
          synthetic get foo @-1
            returnType: (int, String)?
''');
  }

  test_macroDiagnostics_report_atTypeAnnotation_typeAlias_aliasedType() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportAtTypeAnnotation([
  'aliasedType',
])
typedef A = List<int>;
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    typeAliases
      A @81
        aliasedType: List<int>
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: TypeAnnotationMacroDiagnosticTarget
                ElementTypeLocation
                  element: self::@typeAlias::A
                AliasedTypeLocation
            severity: warning
''');
  }

  test_macroDiagnostics_report_contextMessages() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportWithContextMessages()
class A {
  void foo() {}
  void bar() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @62
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: ElementMacroDiagnosticTarget
                element: self::@class::A
            contextMessages
              MacroDiagnosticMessage
                message: See foo
                target: ElementMacroDiagnosticTarget
                  element: self::@class::A::@method::foo
              MacroDiagnosticMessage
                message: See bar
                target: ElementMacroDiagnosticTarget
                  element: self::@class::A::@method::bar
            severity: warning
            correctionMessage: Correction message
        methods
          foo @73
            returnType: void
          bar @89
            returnType: void
''');
  }

  test_macroDiagnostics_report_withoutTarget_error() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportWithoutTargetError()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @61
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: ApplicationMacroDiagnosticTarget
                annotationIndex: 0
            severity: error
''');
  }

  test_macroDiagnostics_report_withoutTarget_info() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportWithoutTargetInfo()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @60
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: ApplicationMacroDiagnosticTarget
                annotationIndex: 0
            severity: info
''');
  }

  test_macroDiagnostics_report_withoutTarget_warning() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ReportWithoutTargetWarning()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @63
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Reported message
              target: ApplicationMacroDiagnosticTarget
                annotationIndex: 0
            severity: warning
''');
  }

  test_macroDiagnostics_throwException_declarationsPhase_class() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ThrowExceptionDeclarationsPhase()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @68
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Macro application failed due to a bug in the macro.
              target: ApplicationMacroDiagnosticTarget
                annotationIndex: 0
            contextMessages
              MacroDiagnosticMessage
                message:
My declarations phase
#0 <cut>
                target: ApplicationMacroDiagnosticTarget
                  annotationIndex: 0
            severity: error
            correctionMessage: Try reporting the failure to the macro author.
''');
  }

  test_macroDiagnostics_throwException_declarationsPhase_class_constructor() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ThrowExceptionDeclarationsPhase()
  A();
}
''');

    configuration.withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        constructors
          @76
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Macro application failed due to a bug in the macro.
                  target: ApplicationMacroDiagnosticTarget
                    annotationIndex: 0
                contextMessages
                  MacroDiagnosticMessage
                    message:
My declarations phase
#0 <cut>
                    target: ApplicationMacroDiagnosticTarget
                      annotationIndex: 0
                severity: error
                correctionMessage: Try reporting the failure to the macro author.
''');
  }

  test_macroDiagnostics_throwException_declarationsPhase_class_field() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ThrowExceptionDeclarationsPhase()
  int foo = 0;
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        fields
          foo @80
            type: int
            shouldUseTypeForInitializerInference: true
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Macro application failed due to a bug in the macro.
                  target: ApplicationMacroDiagnosticTarget
                    annotationIndex: 0
                contextMessages
                  MacroDiagnosticMessage
                    message:
My declarations phase
#0 <cut>
                    target: ApplicationMacroDiagnosticTarget
                      annotationIndex: 0
                severity: error
                correctionMessage: Try reporting the failure to the macro author.
        accessors
          synthetic get foo @-1
            returnType: int
          synthetic set foo= @-1
            parameters
              requiredPositional _foo @-1
                type: int
            returnType: void
''');
  }

  test_macroDiagnostics_throwException_declarationsPhase_class_method() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

class A {
  @ThrowExceptionDeclarationsPhase()
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @33
        methods
          foo @81
            returnType: void
            macroDiagnostics
              MacroDiagnostic
                message: MacroDiagnosticMessage
                  message: Macro application failed due to a bug in the macro.
                  target: ApplicationMacroDiagnosticTarget
                    annotationIndex: 0
                contextMessages
                  MacroDiagnosticMessage
                    message:
My declarations phase
#0 <cut>
                    target: ApplicationMacroDiagnosticTarget
                      annotationIndex: 0
                severity: error
                correctionMessage: Try reporting the failure to the macro author.
''');
  }

  test_macroDiagnostics_throwException_definitionsPhase_class() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ThrowExceptionDefinitionsPhase()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @67
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Macro application failed due to a bug in the macro.
              target: ApplicationMacroDiagnosticTarget
                annotationIndex: 0
            contextMessages
              MacroDiagnosticMessage
                message:
My definitions phase
#0 <cut>
                target: ApplicationMacroDiagnosticTarget
                  annotationIndex: 0
            severity: error
            correctionMessage: Try reporting the failure to the macro author.
''');
  }

  test_macroDiagnostics_throwException_duringInstantiating() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@MacroWithArguments()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false
      ..macroDiagnosticMessagePatterns = [
        'NoSuchMethodError',
        'Closure call with mismatched arguments',
        'Tried calling: MacroWithArguments.MacroWithArguments()',
      ];
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @55
        macroDiagnostics
          ExceptionMacroDiagnostic
            annotationIndex: 0
            contains
              NoSuchMethodError
              Closure call with mismatched arguments
              Tried calling: MacroWithArguments.MacroWithArguments()
''');
  }

  test_macroDiagnostics_throwException_duringIntrospection() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    LibraryElementImpl library;
    try {
      LibraryMacroApplier.testThrowExceptionIntrospection = true;
      library = await buildLibrary(r'''
import 'diagnostic.dart';

@AskFieldsWillThrow()
class A {}
''');
    } finally {
      LibraryMacroApplier.testThrowExceptionIntrospection = false;
    }

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @55
        macroDiagnostics
          ExceptionMacroDiagnostic
            annotationIndex: 0
            message: Intentional exception
''');
  }

  test_macroDiagnostics_throwException_typesPhase_class() async {
    newFile(
      '$testPackageLibPath/diagnostic.dart',
      _getMacroCode('diagnostic.dart'),
    );

    var library = await buildLibrary(r'''
import 'diagnostic.dart';

@ThrowExceptionTypesPhase()
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/diagnostic.dart
  definingUnit
    classes
      class A @61
        macroDiagnostics
          MacroDiagnostic
            message: MacroDiagnosticMessage
              message: Macro application failed due to a bug in the macro.
              target: ApplicationMacroDiagnosticTarget
                annotationIndex: 0
            contextMessages
              MacroDiagnosticMessage
                message:
My types phase
#0 <cut>
                target: ApplicationMacroDiagnosticTarget
                  annotationIndex: 0
            severity: error
            correctionMessage: Try reporting the failure to the macro author.
''');
  }

  test_macroFlag_class() async {
    var library = await buildLibrary(r'''
macro class A {}
''');
    checkElementText(library, r'''
library
  definingUnit
    classes
      macro class A @12
        constructors
          synthetic @-1
''');
  }

  test_macroFlag_classAlias() async {
    var library = await buildLibrary(r'''
mixin M {}
macro class A = Object with M;
''');
    checkElementText(library, r'''
library
  definingUnit
    classes
      macro class alias A @23
        supertype: Object
        mixins
          M
        constructors
          synthetic const @-1
            constantInitializers
              SuperConstructorInvocation
                superKeyword: super @0
                argumentList: ArgumentList
                  leftParenthesis: ( @0
                  rightParenthesis: ) @0
                staticElement: dart:core::@class::Object::@constructor::new
    mixins
      mixin M @6
        superclassConstraints
          Object
''');
  }

  test_notAllowedDeclaration_declarations_class() async {
    if (!keepLinkingLibraries) {
      return;
    }
    useEmptyByteStore();

    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @DeclareInLibrary('class B {}')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @74
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: declarations
                nodeRanges: (43, 10)
---
augment library 'package:test/test.dart';

class B {}
---
''');

    assertDriverStateString(testFile, r'''
files
  /home/test/lib/append.dart
    uri: package:test/append.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_9 package:macros/macros.dart
          library_10 dart:core synthetic
        cycle_0
          dependencies: dart:core package:macros/macros.dart
          libraries: library_0
          apiSignature_0
          users: cycle_1
      referencingFiles: file_1
      unlinkedKey: k00
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_1
      kind: library_1
        libraryImports
          library_0
          library_10 dart:core synthetic
        cycle_1
          dependencies: cycle_0 dart:core
          libraries: library_1
          apiSignature_1
      unlinkedKey: k01
libraryCycles
  /home/test/lib/append.dart
    current: cycle_0
      key: k02
    get: []
    put: [k02]
  /home/test/lib/test.dart
    current: cycle_1
      key: k03
    get: []
    put: [k03]
elementFactory
  hasElement
    package:test/append.dart
    package:test/test.dart
''');
  }

  test_notAllowedDeclaration_declarations_enum() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @DeclareInLibrary('enum B {v}')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @74
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: declarations
                nodeRanges: (43, 10)
---
augment library 'package:test/test.dart';

enum B {v}
---
''');
  }

  test_notAllowedDeclaration_declarations_extension() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @DeclareInLibrary('extension B on int {}')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @85
            returnType: void
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

extension B on int {}
---
      definingUnit
        extensions
          B @53
            extendedType: int
''');
  }

  test_notAllowedDeclaration_declarations_extensionType() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @DeclareInLibrary('extension type B(int it) {}')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @91
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: declarations
                nodeRanges: (43, 27)
---
augment library 'package:test/test.dart';

extension type B(int it) {}
---
''');
  }

  test_notAllowedDeclaration_declarations_mixin() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @DeclareInLibrary('mixin B {}')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @74
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: declarations
                nodeRanges: (43, 10)
---
augment library 'package:test/test.dart';

mixin B {}
---
''');
  }

  test_notAllowedDeclaration_declarations_typedef() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @DeclareInLibrary('typedef B = int;')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @80
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: declarations
                nodeRanges: (43, 16)
---
augment library 'package:test/test.dart';

typedef B = int;
---
''');
  }

  test_notAllowedDeclaration_definitions_class() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @AugmentDefinition(';} class B {}')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @78
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: definitions
                nodeRanges: (85, 10)
---
augment library 'package:test/test.dart';

augment class A {
  augment void foo() ;} class B {}
}
---
''');
  }

  test_notAllowedDeclaration_definitions_class_constructor() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @AugmentDefinition('; A.named();')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @77
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: definitions
                nodeRanges: (84, 10)
---
augment library 'package:test/test.dart';

augment class A {
  augment void foo() ; A.named();
}
---
''');
  }

  test_notAllowedDeclaration_definitions_class_field() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @AugmentDefinition('; int bar = 0;')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @79
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: definitions
                nodeRanges: (84, 12)
---
augment library 'package:test/test.dart';

augment class A {
  augment void foo() ; int bar = 0;
}
---
''');
  }

  test_notAllowedDeclaration_definitions_class_method() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @AugmentDefinition('; void bar() {}')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @80
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: definitions
                nodeRanges: (84, 13)
---
augment library 'package:test/test.dart';

augment class A {
  augment void foo() ; void bar() {}
}
---
''');
  }

  test_notAllowedDeclaration_definitions_enum() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @AugmentDefinition(';} enum B {v}')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @78
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: definitions
                nodeRanges: (85, 10)
---
augment library 'package:test/test.dart';

augment class A {
  augment void foo() ;} enum B {v}
}
---
''');
  }

  test_notAllowedDeclaration_definitions_enum_constants() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @AugmentDefinition(';} augment enum B {v2}')
  void foo() {}
}

enum B {v}
''');

    configuration
      ..withConstructors = false
      ..withConstantInitializers = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @87
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: definitions
                nodeRanges: (101, 2)
---
augment library 'package:test/test.dart';

augment class A {
  augment void foo() ;} augment enum B {v2}
}
---
    enums
      enum B @104
        supertype: Enum
        fields
          static const enumConstant v @107
            type: B
            shouldUseTypeForInitializerInference: false
          synthetic static const values @-1
            type: List<B>
        accessors
          synthetic static get v @-1
            returnType: B
          synthetic static get values @-1
            returnType: List<B>
''');
  }

  test_notAllowedDeclaration_definitions_extension() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @AugmentDefinition(';} extension B on int {}')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @89
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: definitions
                nodeRanges: (85, 21)
---
augment library 'package:test/test.dart';

augment class A {
  augment void foo() ;} extension B on int {}
}
---
''');
  }

  test_notAllowedDeclaration_definitions_extensionType() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @AugmentDefinition(';} extension type B(int it) {}')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @95
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: definitions
                nodeRanges: (85, 27)
---
augment library 'package:test/test.dart';

augment class A {
  augment void foo() ;} extension type B(int it) {}
}
---
''');
  }

  test_notAllowedDeclaration_definitions_function_local() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @AugmentDefinition('{ void bar() {} }')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        methods
          foo @82
            returnType: void
            augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@methodAugmentation::foo
        augmented
          methods
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@methodAugmentation::foo
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

augment class A {
  augment void foo() { void bar() {} }
}
---
      definingUnit
        classes
          augment class A @57
            augmentationTarget: self::@class::A
            methods
              augment foo @76
                returnType: void
                augmentationTarget: self::@class::A::@method::foo
''');
  }

  test_notAllowedDeclaration_definitions_function_topLevel() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @AugmentDefinition(';} void bar() {}')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @81
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: definitions
                nodeRanges: (85, 13)
---
augment library 'package:test/test.dart';

augment class A {
  augment void foo() ;} void bar() {}
}
---
''');
  }

  test_notAllowedDeclaration_definitions_mixin() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @AugmentDefinition(';} mixin B {}')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @78
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: definitions
                nodeRanges: (85, 10)
---
augment library 'package:test/test.dart';

augment class A {
  augment void foo() ;} mixin B {}
}
---
''');
  }

  test_notAllowedDeclaration_definitions_topLevelVariable() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @AugmentDefinition(';} int bar = 0;')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @80
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: definitions
                nodeRanges: (85, 12)
---
augment library 'package:test/test.dart';

augment class A {
  augment void foo() ;} int bar = 0;
}
---
''');
  }

  test_notAllowedDeclaration_definitions_typedef() async {
    var library = await buildLibrary(r'''
import 'append.dart';

class A {
  @AugmentDefinition(';} typedef B = int;')
  void foo() {}
}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @29
        methods
          foo @84
            returnType: void
            macroDiagnostics
              NotAllowedDeclarationDiagnostic
                annotationIndex: 0
                phase: definitions
                nodeRanges: (85, 16)
---
augment library 'package:test/test.dart';

augment class A {
  augment void foo() ;} typedef B = int;
}
---
''');
  }
}

@reflectiveTest
class MacroElementsTest_fromBytes extends MacroElementsTest {
  @override
  bool get keepLinkingLibraries => false;
}

@reflectiveTest
class MacroElementsTest_keepLinking extends MacroElementsTest {
  @override
  bool get keepLinkingLibraries => true;
}

@reflectiveTest
class MacroExampleTest extends MacroElementsBaseTest {
  @override
  bool get keepLinkingLibraries => true;

  test_autoToString() async {
    _addExampleMacro('auto_to_string.dart');

    var library = await buildLibrary(r'''
import 'auto_to_string.dart';

@AutoToString()
class A {
  final int foo;
  final int bar;
  A(this.foo, this.bar);
}
''');

    configuration
      ..withConstructors = false
      ..withReferences = true
      ..withMetadata = false;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/auto_to_string.dart
  definingUnit
    reference: self
    classes
      class A @53
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        fields
          final foo @69
            reference: self::@class::A::@field::foo
            type: int
          final bar @86
            reference: self::@class::A::@field::bar
            type: int
        accessors
          synthetic get foo @-1
            reference: self::@class::A::@getter::foo
            returnType: int
          synthetic get bar @-1
            reference: self::@class::A::@getter::bar
            returnType: int
        augmented
          fields
            self::@class::A::@field::bar
            self::@class::A::@field::foo
          accessors
            self::@class::A::@getter::bar
            self::@class::A::@getter::foo
          methods
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@methodAugmentation::toString
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class A {
  @prefix0.override
  prefix0.String toString();
  augment prefix0.String toString() {
    // You can add breakpoints here!
    return """
A {
  foo: ${this.foo}
  bar: ${this.bar}
}""";
  }
}
---
      imports
        dart:core as prefix0 @65
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @89
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            methods
              abstract toString @130
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@method::toString
                returnType: String
                augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@methodAugmentation::toString
              augment toString @167
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@methodAugmentation::toString
                returnType: String
                augmentationTarget: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@method::toString
''');
  }

  test_jsonSerializable() async {
    _addExampleMacro('json_key.dart');
    _addExampleMacro('json_serializable.dart');

    var library = await buildLibrary(r'''
import 'json_serializable.dart';

@JsonSerializable()
class A {
  final int foo;
  final int bar;
}
''');

    configuration
      ..withReferences = true
      ..withMetadata = false;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/json_serializable.dart
  definingUnit
    reference: self
    classes
      class A @60
        reference: self::@class::A
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
        fields
          final foo @76
            reference: self::@class::A::@field::foo
            type: int
          final bar @93
            reference: self::@class::A::@field::bar
            type: int
        accessors
          synthetic get foo @-1
            reference: self::@class::A::@getter::foo
            returnType: int
          synthetic get bar @-1
            reference: self::@class::A::@getter::bar
            returnType: int
        augmented
          fields
            self::@class::A::@field::bar
            self::@class::A::@field::foo
          constructors
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructorAugmentation::fromJson
          accessors
            self::@class::A::@getter::bar
            self::@class::A::@getter::foo
          methods
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@methodAugmentation::toJson
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/json_serializable.dart' as prefix0;
import 'dart:core' as prefix1;

augment class A {
  @prefix0.FromJson()
  external A.fromJson(prefix1.Map<prefix1.String, prefix1.Object?> json);
  @prefix0.ToJson()
  external prefix1.Map<prefix1.String, prefix1.Object?> toJson();
  augment A.fromJson(prefix1.Map<prefix1.String, prefix1.Object?> json, )
      : this.foo = json['foo'] as prefix1.int,
        this.bar = json['bar'] as prefix1.int;
  augment prefix1.Map<prefix1.String, prefix1.Object?> toJson() {
    var json = <prefix1.String, prefix1.Object?>{};
    json['foo'] = this.foo;
json['bar'] = this.bar;
    return json;
  }
}
---
      imports
        package:test/json_serializable.dart as prefix0 @91
        dart:core as prefix1 @122
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          augment class A @146
            reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A
            augmentationTarget: self::@class::A
            constructors
              external fromJson @185
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructor::fromJson
                periodOffset: 184
                nameEnd: 193
                parameters
                  requiredPositional json @239
                    type: Map<String, Object?>
                augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructorAugmentation::fromJson
              augment fromJson @344
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructorAugmentation::fromJson
                periodOffset: 343
                nameEnd: 352
                parameters
                  requiredPositional json @398
                    type: Map<String, Object?>
                augmentationTarget: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@constructor::fromJson
            methods
              external toJson @322
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@method::toJson
                returnType: Map<String, Object?>
                augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@methodAugmentation::toJson
              augment toJson @555
                reference: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@methodAugmentation::toJson
                returnType: Map<String, Object?>
                augmentationTarget: self::@augmentation::package:test/test.macro.dart::@classAugmentation::A::@method::toJson
''');
  }

  test_observable() async {
    _addExampleMacro('observable.dart');

    var library = await buildLibrary(r'''
import 'observable.dart';

class A {
  @Observable()
  int _foo = 0;
}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

import 'dart:core' as prefix0;

augment class A {
  prefix0.int get foo => this._foo;
  set foo(prefix0.int val) {
    prefix0.print('Setting foo to ${val}');
    this._foo = val;
  }
}
''');
  }

  void _addExampleMacro(String fileName) {
    var code = _getMacroCode('example/$fileName');
    newFile('$testPackageLibPath/$fileName', code);
  }
}

@reflectiveTest
class MacroIncrementalTest extends MacroElementsBaseTest {
  @override
  bool get keepLinkingLibraries => true;

  @override
  bool get retainDataForTesting => true;

  @override
  Future<void> setUp() async {
    await super.setUp();
    useEmptyByteStore();
  }

  test_changeDependency_noIntrospect() async {
    var a = newFile('$testPackageLibPath/a.dart', r'''
class A {}
''');

    var library1 = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType('  void foo() {}')
class X {}
''');

    var expectedLibraryText = r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  definingUnit
    classes
      class X @80
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::X
        augmented
          methods
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::X::@method::foo
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

augment class X {
  void foo() {}
}
---
      definingUnit
        classes
          augment class X @57
            augmentationTarget: self::@class::X
            methods
              foo @68
                returnType: void
''';

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library1, expectedLibraryText);

    // Generated and put into the cache.
    _assertMacroCachedGenerated(testFile, r'''
/home/test/lib/test.dart
  usedCached
  generated
    /home/test/lib/test.dart
''');

    modifyFile2(a, r'''
class A2 {}
''');
    driverFor(testFile).changeFile2(a);
    await contextFor(testFile).applyPendingFileChanges();

    var library2 = await buildFileLibrary(testFile);
    checkElementText(library2, expectedLibraryText);

    // Used cached, no new generated.
    _assertMacroCachedGenerated(testFile, r'''
/home/test/lib/test.dart
  usedCached
    /home/test/lib/test.dart
  generated
    /home/test/lib/test.dart
''');
  }

  test_resolveIdentifier_class_notChanged() async {
    var a = newFile('$testPackageLibPath/a.dart', r'''
class A {}
''');

    var library1 = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareInType('  {{package:test/a.dart@A}} foo() {}')
class X {}
''');

    var expectedLibraryText = r'''
library
  imports
    package:test/append.dart
    package:test/a.dart
  definingUnit
    classes
      class X @101
        augmentation: self::@augmentation::package:test/test.macro.dart::@classAugmentation::X
        augmented
          methods
            self::@augmentation::package:test/test.macro.dart::@classAugmentation::X::@method::foo
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

augment class X {
  prefix0.A foo() {}
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          augment class X @99
            augmentationTarget: self::@class::X
            methods
              foo @115
                returnType: A
''';

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library1, expectedLibraryText);

    // Generated and put into the cache.
    _assertMacroCachedGenerated(testFile, r'''
/home/test/lib/test.dart
  usedCached
  generated
    /home/test/lib/test.dart
''');

    modifyFile2(a, r'''
class A {}
class B {}
''');
    driverFor(testFile).changeFile2(a);
    await contextFor(testFile).applyPendingFileChanges();

    var library2 = await buildFileLibrary(testFile);
    checkElementText(library2, expectedLibraryText);

    // Cannot prove that `package:test/test.dart@A` is still there.
    // So, not used cached.
    // TODO(scheglov): Make it use cached.
    _assertMacroCachedGenerated(testFile, r'''
/home/test/lib/test.dart
  usedCached
  generated
    /home/test/lib/test.dart
    /home/test/lib/test.dart
''');
  }

  void _assertMacroCachedGenerated(File targetFile, String expected) {
    var buffer = StringBuffer();
    var sink = TreeStringSink(
      sink: buffer,
      indent: '',
    );

    var testData = driverFor(testFile).testView!.libraryContext;
    for (var entry in testData.libraryCycles.entries) {
      if (entry.key.map((fd) => fd.file).contains(targetFile)) {
        var fileListStr = entry.key
            .map((fileData) => fileData.file.posixPath)
            .sorted()
            .join(' ');
        sink.writelnWithIndent(fileListStr);
        sink.withIndent(() {
          sink.writelnWithIndent('usedCached');
          sink.withIndent(() {
            for (var files in entry.value.macrosUsedCached) {
              sink.writelnWithIndent(files.map((f) => f.posixPath).join(' '));
            }
          });

          sink.writelnWithIndent('generated');
          sink.withIndent(() {
            for (var files in entry.value.macrosGenerated) {
              sink.writelnWithIndent(files.map((f) => f.posixPath).join(' '));
            }
          });
        });
      }
    }

    var actual = buffer.toString();
    if (actual != expected) {
      print('-------- Actual --------');
      print('$actual------------------------');
      NodeTextExpectationsCollector.add(actual);
    }
    expect(actual, expected);
  }
}

@reflectiveTest
class MacroIntrospectElementTest extends MacroElementsBaseTest {
  @override
  bool get keepLinkingLibraries => true;

  test_class_constructor_flags_isFactory() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  A();
  factory A.named() => A();
}
''');

    await _assertIntrospectText('A', withUnnamedConstructor: true, r'''
class A
  superclass: Object
  constructors
    <unnamed>
      flags: hasBody hasStatic
      returnType: A
    named
      flags: hasBody hasStatic isFactory
      returnType: A
''');
  }

  test_class_constructor_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;

class A {
  @a
  A();
}
''');

    await _assertIntrospectText('A', withUnnamedConstructor: true, r'''
class A
  superclass: Object
  constructors
    <unnamed>
      flags: hasBody hasStatic
      metadata
        IdentifierMetadataAnnotation
          identifier: a
      returnType: A
''');
  }

  test_class_constructor_named() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  A.named();
}
''');

    await _assertIntrospectText('A', withUnnamedConstructor: true, r'''
class A
  superclass: Object
  constructors
    named
      flags: hasBody hasStatic
      returnType: A
''');
  }

  test_class_constructor_namedParameters() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  A({required int a, String? b});
}
''');

    await _assertIntrospectText('A', withUnnamedConstructor: true, r'''
class A
  superclass: Object
  constructors
    <unnamed>
      flags: hasBody hasStatic
      namedParameters
        a
          flags: isNamed isRequired
          type: int
        b
          flags: isNamed
          type: String?
      returnType: A
''');
  }

  test_class_constructor_positionalParameters() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  A(int a, [String? b]);
}
''');

    await _assertIntrospectText('A', withUnnamedConstructor: true, r'''
class A
  superclass: Object
  constructors
    <unnamed>
      flags: hasBody hasStatic
      positionalParameters
        a
          flags: isRequired
          type: int
        b
          type: String?
      returnType: A
''');
  }

  test_class_field_flag_hasConst() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  static const int foo = 0;
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  fields
    foo
      flags: hasConst hasInitializer hasStatic
      type: int
''');
  }

  test_class_field_flag_hasExternal() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  external int foo;
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  fields
    foo
      flags: hasExternal
      type: int
''');
  }

  test_class_field_flag_hasFinal() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  final int foo = 0;
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  fields
    foo
      flags: hasFinal hasInitializer
      type: int
''');
  }

  test_class_field_flag_hasLate() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  late int foo;
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  fields
    foo
      flags: hasLate
      type: int
''');
  }

  test_class_field_flag_hasStatic() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  static int foo = 0;
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  fields
    foo
      flags: hasInitializer hasStatic
      type: int
''');
  }

  test_class_field_metadata_identifier() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;

class A {
  @a
  int? foo;
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  fields
    foo
      metadata
        IdentifierMetadataAnnotation
          identifier: a
      type: int?
''');
  }

  test_class_field_metadata_identifier_imported() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    newFile('$testPackageLibPath/b.dart', r'''
import 'a.dart';

class A {
  @a
  int? foo;
}
''');

    await _assertIntrospectText('A', uriStr: 'package:test/b.dart', r'''
class A
  superclass: Object
  fields
    foo
      metadata
        IdentifierMetadataAnnotation
          identifier: a
      type: int?
''');
  }

  test_class_fields_augmented() async {
    newFile('$testPackageLibPath/a.dart', r'''
import augment 'b.dart';

class A {
  final int foo = 0;
}
''');

    newFile('$testPackageLibPath/b.dart', r'''
augment library 'a.dart';

augment class A {
  final int bar = 0;
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  fields
    foo
      flags: hasFinal hasInitializer
      type: int
    bar
      flags: hasFinal hasInitializer
      type: int
''');
  }

  test_class_flags_hasAbstract() async {
    newFile('$testPackageLibPath/a.dart', r'''
abstract class A {}
''');

    await _assertIntrospectText('A', r'''
class A
  flags: hasAbstract
  superclass: Object
''');
  }

  test_class_getter() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  int get foo => 0;
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  methods
    foo
      flags: hasBody isGetter
      returnType: int
''');
  }

  test_class_interfaces() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {}
class B {}
class C implements A, B {}
''');

    await _assertIntrospectText('C', r'''
class C
  superclass: Object
  interfaces
    A
    B
''');
  }

  test_class_metadata_augmented() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
const b = 1;

import augment 'b.dart';

@a
class A {}
''');

    newFile('$testPackageLibPath/b.dart', r'''
augment library 'a.dart';

@b
augment class A {}
''');

    await _assertIntrospectText('A', r'''
class A
  metadata
    IdentifierMetadataAnnotation
      identifier: a
    IdentifierMetadataAnnotation
      identifier: b
  superclass: Object
''');
  }

  test_class_metadata_constructor_named() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A.named()
}

@A.named()
class B {}
''');

    await _assertIntrospectText('B', r'''
class B
  metadata
    ConstructorMetadataAnnotation
      type: A
      constructorName: named
  superclass: Object
''');
  }

  test_class_metadata_constructor_named_imported() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A.named()
}
''');

    newFile('$testPackageLibPath/b.dart', r'''
import 'a.dart';

@A.named()
class B {}
''');

    await _assertIntrospectText('B', uriStr: 'package:test/b.dart', r'''
class B
  metadata
    ConstructorMetadataAnnotation
      type: A
      constructorName: named
  superclass: Object
''');
  }

  test_class_metadata_constructor_named_imported_withPrefix() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A.named()
}
''');

    newFile('$testPackageLibPath/b.dart', r'''
import 'a.dart' as prefix;

@prefix.A.named()
class B {}
''');

    await _assertIntrospectText('B', uriStr: 'package:test/b.dart', r'''
class B
  metadata
    ConstructorMetadataAnnotation
      type: A
      constructorName: named
  superclass: Object
''');
  }

  test_class_metadata_constructor_unnamed() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A()
}

@A()
class B {}
''');

    await _assertIntrospectText('B', r'''
class B
  metadata
    ConstructorMetadataAnnotation
      type: A
  superclass: Object
''');
  }

  test_class_metadata_constructor_unnamed_imported() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A()
}
''');

    newFile('$testPackageLibPath/b.dart', r'''
import 'a.dart';

@A()
class B {}
''');

    await _assertIntrospectText('B', uriStr: 'package:test/b.dart', r'''
class B
  metadata
    ConstructorMetadataAnnotation
      type: A
  superclass: Object
''');
  }

  test_class_metadata_constructor_unnamed_imported_withPrefix() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A()
}
''');

    newFile('$testPackageLibPath/b.dart', r'''
import 'a.dart' as prefix;

@prefix.A()
class B {}
''');

    await _assertIntrospectText('B', uriStr: 'package:test/b.dart', r'''
class B
  metadata
    ConstructorMetadataAnnotation
      type: A
  superclass: Object
''');
  }

  test_class_metadata_identifier() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;

@a
class A {}
''');

    await _assertIntrospectText('A', r'''
class A
  metadata
    IdentifierMetadataAnnotation
      identifier: a
  superclass: Object
''');
  }

  test_class_metadata_identifier_imported() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    newFile('$testPackageLibPath/b.dart', r'''
import 'a.dart';

@a
class A {}
''');

    await _assertIntrospectText('A', uriStr: 'package:test/b.dart', r'''
class A
  metadata
    IdentifierMetadataAnnotation
      identifier: a
  superclass: Object
''');
  }

  test_class_metadata_identifier_imported_withPrefix() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    newFile('$testPackageLibPath/b.dart', r'''
import 'a.dart' as prefix;

@prefix.a
class A {}
''');

    await _assertIntrospectText('A', uriStr: 'package:test/b.dart', r'''
class A
  metadata
    IdentifierMetadataAnnotation
      identifier: a
  superclass: Object
''');
  }

  test_class_method_flags_hasBody_false() async {
    newFile('$testPackageLibPath/a.dart', r'''
abstract class A {
  void foo();
}
''');

    await _assertIntrospectText('A', r'''
class A
  flags: hasAbstract
  superclass: Object
  methods
    foo
      returnType: void
''');
  }

  test_class_method_flags_hasExternal() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  external void foo();
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  methods
    foo
      flags: hasBody hasExternal
      returnType: void
''');
  }

  test_class_method_flags_hasStatic() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  static void foo() {}
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  methods
    foo
      flags: hasBody hasStatic
      returnType: void
''');
  }

  test_class_method_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    newFile('$testPackageLibPath/b.dart', r'''
import 'a.dart';

class A {
  @a
  void foo() {}
}
''');

    await _assertIntrospectText('A', uriStr: 'package:test/b.dart', r'''
class A
  superclass: Object
  methods
    foo
      flags: hasBody
      metadata
        IdentifierMetadataAnnotation
          identifier: a
      returnType: void
''');
  }

  test_class_method_namedParameters() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  void foo({required int a, String? b}) {}
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  methods
    foo
      flags: hasBody
      namedParameters
        a
          flags: isNamed isRequired
          type: int
        b
          flags: isNamed
          type: String?
      returnType: void
''');
  }

  test_class_method_namedParameters_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    newFile('$testPackageLibPath/b.dart', r'''
import 'a.dart';

class A {
  void foo({@a required int x}) {}
}
''');

    await _assertIntrospectText('A', uriStr: 'package:test/b.dart', r'''
class A
  superclass: Object
  methods
    foo
      flags: hasBody
      namedParameters
        x
          flags: isNamed isRequired
          metadata
            IdentifierMetadataAnnotation
              identifier: a
          type: int
      returnType: void
''');
  }

  test_class_method_positionalParameters() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  void foo(int a, [String? b]) {}
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  methods
    foo
      flags: hasBody
      positionalParameters
        a
          flags: isRequired
          type: int
        b
          type: String?
      returnType: void
''');
  }

  test_class_method_positionalParameters_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    newFile('$testPackageLibPath/b.dart', r'''
import 'a.dart';

class A {
  void foo(@a int x) {}
}
''');

    await _assertIntrospectText('A', uriStr: 'package:test/b.dart', r'''
class A
  superclass: Object
  methods
    foo
      flags: hasBody
      positionalParameters
        x
          flags: isRequired
          metadata
            IdentifierMetadataAnnotation
              identifier: a
          type: int
      returnType: void
''');
  }

  test_class_methods_augmented() async {
    newFile('$testPackageLibPath/a.dart', r'''
import augment 'b.dart';

class A {
  void foo() {}
}
''');

    newFile('$testPackageLibPath/b.dart', r'''
augment library 'a.dart';

augment class A {
  void bar() {}
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  methods
    foo
      flags: hasBody
      returnType: void
    bar
      flags: hasBody
      returnType: void
''');
  }

  test_class_mixins() async {
    newFile('$testPackageLibPath/a.dart', r'''
mixin M1 {}
mixin M2 {}
class C with M1, M2 {}
''');

    await _assertIntrospectText('C', r'''
class C
  superclass: Object
  mixins
    M1
    M2
''');
  }

  test_class_setter() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  set foo(int value) {}
}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  methods
    foo
      flags: hasBody isSetter
      positionalParameters
        value
          flags: isRequired
          type: int
      returnType: void
''');
  }

  test_class_superclass() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A<T> {}
class B<U> extends A<U> {}
''');

    await _assertIntrospectText('B', r'''
class B
  superclass: A<U>
  typeParameters
    U
''');
  }

  test_class_typeParameters() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A<T, U extends List<T>> {}
''');

    await _assertIntrospectText('A', r'''
class A
  superclass: Object
  typeParameters
    T
    U
      bound: List<T>
''');
  }

  test_classAlias_interfaces() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {}
mixin M {}
class I {}
class J {}

class C = A with M implements I, J;
''');

    await _assertIntrospectText('C', r'''
class C
  superclass: A
  mixins
    M
  interfaces
    I
    J
''');
  }

  test_classAlias_typeParameters() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A<T1> {}
mixin M<U1> {}

class C<T2, U2> = A<T2> with M<U2>;
''');

    await _assertIntrospectText('C', r'''
class C
  superclass: A<T2>
  typeParameters
    T2
    U2
  mixins
    M<U2>
''');
  }

  test_enum_fields() async {
    newFile('$testPackageLibPath/a.dart', r'''
enum A {
  v(0);
  final int foo;
  const A(this.foo);
}
''');

    await _assertIntrospectText('A', r'''
enum A
  values
    v
  fields
    foo
      flags: hasFinal
      type: int
''');
  }

  test_enum_getters() async {
    newFile('$testPackageLibPath/a.dart', r'''
enum A {
  v;
  int get foo => 0;
}
''');

    await _assertIntrospectText('A', r'''
enum A
  values
    v
  methods
    foo
      flags: hasBody isGetter
      returnType: int
''');
  }

  test_enum_interfaces() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {}
class B {}

enum X implements A, B {
  v
}
''');

    await _assertIntrospectText('X', r'''
enum X
  interfaces
    A
    B
  values
    v
''');
  }

  test_enum_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
@a1
@a2
enum X {
  v
}

const a1 = 0;
const a2 = 0;
''');

    await _assertIntrospectText('X', r'''
enum X
  metadata
    IdentifierMetadataAnnotation
      identifier: a1
    IdentifierMetadataAnnotation
      identifier: a2
  values
    v
''');
  }

  test_enum_methods() async {
    newFile('$testPackageLibPath/a.dart', r'''
enum A {
  v;
  void foo() {}
}
''');

    await _assertIntrospectText('A', r'''
enum A
  values
    v
  methods
    foo
      flags: hasBody
      returnType: void
''');
  }

  test_enum_mixins() async {
    newFile('$testPackageLibPath/a.dart', r'''
mixin A {}
mixin B {}

enum X with A, B {
  v
}
''');

    await _assertIntrospectText('X', r'''
enum X
  mixins
    A
    B
  values
    v
''');
  }

  test_enum_setters() async {
    newFile('$testPackageLibPath/a.dart', r'''
enum A {
  v;
  set foo(int value) {}
}
''');

    await _assertIntrospectText('A', r'''
enum A
  values
    v
  methods
    foo
      flags: hasBody isSetter
      positionalParameters
        value
          flags: isRequired
          type: int
      returnType: void
''');
  }

  test_enum_typeParameters() async {
    newFile('$testPackageLibPath/a.dart', r'''
enum A<T> {
  v
}
''');

    await _assertIntrospectText('A', r'''
enum A
  typeParameters
    T
  values
    v
''');
  }

  test_enum_values() async {
    newFile('$testPackageLibPath/a.dart', r'''
enum X with A, B {
  foo, bar
}
''');

    await _assertIntrospectText('X', r'''
enum X
  values
    foo
    bar
''');
  }

  test_extension_getters() async {
    newFile('$testPackageLibPath/a.dart', r'''
extension A on int {
  int get foo => 0;
}
''');

    await _assertIntrospectText('A', r'''
extension A
  onType: int
  methods
    foo
      flags: hasBody isGetter
      returnType: int
''');
  }

  test_extension_metadata_identifier() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;

@a
extension A on int {}
''');

    await _assertIntrospectText('A', r'''
extension A
  metadata
    IdentifierMetadataAnnotation
      identifier: a
  onType: int
''');
  }

  test_extension_methods() async {
    newFile('$testPackageLibPath/a.dart', r'''
extension A on int {
  void foo() {}
}
''');

    await _assertIntrospectText('A', r'''
extension A
  onType: int
  methods
    foo
      flags: hasBody
      returnType: void
''');
  }

  test_extension_setters() async {
    newFile('$testPackageLibPath/a.dart', r'''
extension A on int {
  set foo(int value) {}
}
''');

    await _assertIntrospectText('A', r'''
extension A
  onType: int
  methods
    foo
      flags: hasBody isSetter
      positionalParameters
        value
          flags: isRequired
          type: int
      returnType: void
''');
  }

  test_extension_typeParameters() async {
    newFile('$testPackageLibPath/a.dart', r'''
extension A<T> on Map<int, T> {}
''');

    await _assertIntrospectText('A', r'''
extension A
  typeParameters
    T
  onType: Map<int, T>
''');
  }

  test_extensionType_getters() async {
    newFile('$testPackageLibPath/a.dart', r'''
extension type A(int it) {
  int get foo => 0;
}
''');

    await _assertIntrospectText('A', r'''
extension type A
  representationType: int
  fields
    it
      flags: hasFinal
      type: int
  methods
    foo
      flags: hasBody isGetter
      returnType: int
''');
  }

  test_extensionType_metadata_identifier() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;

@a
extension type A(int it) {}
''');

    await _assertIntrospectText('A', r'''
extension type A
  metadata
    IdentifierMetadataAnnotation
      identifier: a
  representationType: int
  fields
    it
      flags: hasFinal
      type: int
''');
  }

  test_extensionType_methods() async {
    newFile('$testPackageLibPath/a.dart', r'''
extension type A(int it) {
  void foo() {}
}
''');

    await _assertIntrospectText('A', r'''
extension type A
  representationType: int
  fields
    it
      flags: hasFinal
      type: int
  methods
    foo
      flags: hasBody
      returnType: void
''');
  }

  test_extensionType_typeParameters() async {
    newFile('$testPackageLibPath/a.dart', r'''
extension type A<T>(int it) {}
''');

    await _assertIntrospectText('A', r'''
extension type A
  typeParameters
    T
  representationType: int
  fields
    it
      flags: hasFinal
      type: int
''');
  }

  test_functionType_formalParameters_namedOptional_simpleFormalParameter() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo(void Function(int a, {int? b, int? c}) t) {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  positionalParameters
    t
      flags: isRequired
      type: void Function(int a, {int? b}, {int? c})
  returnType: void
''');
  }

  test_functionType_formalParameters_namedRequired_simpleFormalParameter() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo(void Function(int a, {required int b, required int c}) t) {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  positionalParameters
    t
      flags: isRequired
      type: void Function(int a, {required int b}, {required int c})
  returnType: void
''');
  }

  test_functionType_formalParameters_positionalOptional_simpleFormalParameter() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo(void Function(int a, [int b, int c]) t) {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  positionalParameters
    t
      flags: isRequired
      type: void Function(int a, [int b], [int c])
  returnType: void
''');
  }

  test_functionType_formalParameters_positionalOptional_simpleFormalParameter_noName() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo(void Function(int a, [int, int]) t) {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  positionalParameters
    t
      flags: isRequired
      type: void Function(int a, [int ], [int ])
  returnType: void
''');
  }

  test_functionType_formalParameters_positionalRequired_simpleFormalParameter() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo(void Function(int a, double b) t) {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  positionalParameters
    t
      flags: isRequired
      type: void Function(int a, double b)
  returnType: void
''');
  }

  test_functionType_formalParameters_positionalRequired_simpleFormalParameter_noName() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo(void Function(int, double) t) {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  positionalParameters
    t
      flags: isRequired
      type: void Function(int , double )
  returnType: void
''');
  }

  test_functionType_nullable() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo(void Function()? t) {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  positionalParameters
    t
      flags: isRequired
      type: void Function()?
  returnType: void
''');
  }

  test_functionType_returnType() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo(void Function() t) {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  positionalParameters
    t
      flags: isRequired
      type: void Function()
  returnType: void
''');
  }

  test_functionType_returnType_omitted() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo(Function() t) {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  positionalParameters
    t
      flags: isRequired
      type: dynamic Function()
  returnType: void
''');
  }

  test_functionType_typeParameters() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo(void Function<T, U extends num>() t) {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  positionalParameters
    t
      flags: isRequired
      type: void Function<T, U extends num>()
  returnType: void
''');
  }

  test_mixin_field() async {
    newFile('$testPackageLibPath/a.dart', r'''
mixin A {
  final int foo = 0;
}
''');

    await _assertIntrospectText('A', r'''
mixin A
  superclassConstraints
    Object
  fields
    foo
      flags: hasFinal hasInitializer
      type: int
''');
  }

  test_mixin_field_metadata_identifier() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;

mixin A {
  @a
  int? foo;
}
''');

    await _assertIntrospectText('A', r'''
mixin A
  superclassConstraints
    Object
  fields
    foo
      metadata
        IdentifierMetadataAnnotation
          identifier: a
      type: int?
''');
  }

  test_mixin_field_metadata_identifier_imported() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    newFile('$testPackageLibPath/b.dart', r'''
import 'a.dart';

mixin A {
  @a
  int? foo;
}
''');

    await _assertIntrospectText('A', uriStr: 'package:test/b.dart', r'''
mixin A
  superclassConstraints
    Object
  fields
    foo
      metadata
        IdentifierMetadataAnnotation
          identifier: a
      type: int?
''');
  }

  test_mixin_getter() async {
    newFile('$testPackageLibPath/a.dart', r'''
mixin A {
  int get foo => 0;
}
''');

    await _assertIntrospectText('A', r'''
mixin A
  superclassConstraints
    Object
  methods
    foo
      flags: hasBody isGetter
      returnType: int
''');
  }

  test_mixin_metadata_augmented() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
const b = 1;

import augment 'b.dart';

@a
mixin A {}
''');

    newFile('$testPackageLibPath/b.dart', r'''
augment library 'a.dart';

@b
augment mixin A {}
''');

    await _assertIntrospectText('A', r'''
mixin A
  metadata
    IdentifierMetadataAnnotation
      identifier: a
    IdentifierMetadataAnnotation
      identifier: b
  superclassConstraints
    Object
''');
  }

  test_mixin_metadata_identifier() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;

@a
mixin A {}
''');

    await _assertIntrospectText('A', r'''
mixin A
  metadata
    IdentifierMetadataAnnotation
      identifier: a
  superclassConstraints
    Object
''');
  }

  test_mixin_method() async {
    newFile('$testPackageLibPath/a.dart', r'''
mixin A {
  void foo() {}
}
''');

    await _assertIntrospectText('A', r'''
mixin A
  superclassConstraints
    Object
  methods
    foo
      flags: hasBody
      returnType: void
''');
  }

  test_mixin_setter() async {
    newFile('$testPackageLibPath/a.dart', r'''
mixin A {
  set foo(int value) {}
}
''');

    await _assertIntrospectText('A', r'''
mixin A
  superclassConstraints
    Object
  methods
    foo
      flags: hasBody isSetter
      positionalParameters
        value
          flags: isRequired
          type: int
      returnType: void
''');
  }

  test_unit_function() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo() {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  returnType: void
''');
  }

  test_unit_function_flags_hasExternal() async {
    newFile('$testPackageLibPath/a.dart', r'''
external void foo() {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody hasExternal
  returnType: void
''');
  }

  test_unit_function_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
@a1
@a2
void foo() {}

const a1 = 0;
const a2 = 0;
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  metadata
    IdentifierMetadataAnnotation
      identifier: a1
    IdentifierMetadataAnnotation
      identifier: a2
  returnType: void
''');
  }

  test_unit_function_namedParameters() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo({required int a, String? b}) {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  namedParameters
    a
      flags: isNamed isRequired
      type: int
    b
      flags: isNamed
      type: String?
  returnType: void
''');
  }

  test_unit_function_positionalParameters() async {
    newFile('$testPackageLibPath/a.dart', r'''
void foo(int a, [String? b]) {}
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody
  positionalParameters
    a
      flags: isRequired
      type: int
    b
      type: String?
  returnType: void
''');
  }

  test_unit_getter() async {
    newFile('$testPackageLibPath/a.dart', r'''
int get foo => 0;
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasBody isGetter
  returnType: int
''');
  }

  test_unit_setter() async {
    newFile('$testPackageLibPath/a.dart', r'''
set foo(int value) {}
''');

    await _assertIntrospectText('foo=', r'''
foo
  flags: hasBody isSetter
  positionalParameters
    value
      flags: isRequired
      type: int
  returnType: void
''');
  }

  test_unit_typeAlias() async {
    newFile('$testPackageLibPath/a.dart', r'''
typedef A = List<int>;
''');

    await _assertIntrospectText('A', r'''
typedef A
  aliasedType: List<int>
''');
  }

  test_unit_variable() async {
    newFile('$testPackageLibPath/a.dart', r'''
final foo = 0;
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasFinal hasInitializer
  type: int
''');
  }

  test_unit_variable_flags_hasConst_true() async {
    newFile('$testPackageLibPath/a.dart', r'''
const foo = 0;
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasConst hasInitializer
  type: int
''');
  }

  test_unit_variable_flags_hasExternal_true() async {
    newFile('$testPackageLibPath/a.dart', r'''
external int foo;
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasExternal
  type: int
''');
  }

  test_unit_variable_flags_hasFinal_false() async {
    newFile('$testPackageLibPath/a.dart', r'''
var foo = 0;
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasInitializer
  type: int
''');
  }

  test_unit_variable_flags_hasInitializer_false() async {
    newFile('$testPackageLibPath/a.dart', r'''
int? foo;
''');

    await _assertIntrospectText('foo', r'''
foo
  type: int?
''');
  }

  test_unit_variable_flags_hasLate_true() async {
    newFile('$testPackageLibPath/a.dart', r'''
late int foo;
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasLate
  type: int
''');
  }

  test_unit_variable_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
@a1
@a2
final foo = 0;

const a1 = 0;
const a2 = 0;
''');

    await _assertIntrospectText('foo', r'''
foo
  flags: hasFinal hasInitializer
  metadata
    IdentifierMetadataAnnotation
      identifier: a1
    IdentifierMetadataAnnotation
      identifier: a2
  type: int
''');
  }

  Future<void> _assertIntrospectText(
    String name,
    String expected, {
    String uriStr = 'package:test/a.dart',
    bool withUnnamedConstructor = false,
  }) async {
    newFile(
      '$testPackageLibPath/introspect.dart',
      _getMacroCode('introspect.dart'),
    );

    await _assertIntrospectDefinitionText(
      '''
import '$uriStr';
import 'introspect.dart';
''',
      expected,
      name: name,
      uriStr: uriStr,
      withUnnamedConstructor: withUnnamedConstructor,
    );
  }
}

@reflectiveTest
class MacroIntrospectNodeDefinitionsTest extends MacroElementsBaseTest {
  @override
  bool get keepLinkingLibraries => true;

  test_inferType_constructor_fieldFormalParameter() async {
    await _assertIntrospectText('A', r'''
class A {
  final int foo;
  A.named(this.foo);
}
''', r'''
class A
  constructors
    named
      flags: hasStatic
      positionalParameters
        foo
          flags: isRequired
          type: OmittedType
            inferred: int
      returnType: A
  fields
    foo
      flags: hasFinal
      type: int
''');
  }

  test_inferType_fieldInstance_fromInitializer() async {
    await _assertIntrospectText('X', r'''
class X {
  final foo = 0;
}
''', r'''
class X
  fields
    foo
      flags: hasFinal hasInitializer
      type: OmittedType
        inferred: int
''');
  }

  test_inferType_fieldInstance_fromSuper() async {
    await _assertIntrospectText('X', r'''
class A {
  int get foo => 0;
}

class X extends A {
  final foo = 0;
}
''', r'''
class X
  superclass: A
  fields
    foo
      flags: hasFinal hasInitializer
      type: OmittedType
        inferred: int
''');
  }

  test_inferType_fieldStatic() async {
    await _assertIntrospectText('A', r'''
class A {
  static final foo;
}
''', r'''
class A
  fields
    foo
      flags: hasFinal hasStatic
      type: OmittedType
        inferred: dynamic
''');
  }

  test_inferType_fieldStatic_fromInitializer() async {
    await _assertIntrospectText('A', r'''
class A {
  static final foo = 0;
}
''', r'''
class A
  fields
    foo
      flags: hasFinal hasInitializer hasStatic
      type: OmittedType
        inferred: int
''');
  }

  test_inferType_function_formalParameter() async {
    await _assertIntrospectText('foo', r'''
void foo(a) => 0;
''', r'''
foo
  flags: hasBody
  positionalParameters
    a
      flags: isRequired
      type: OmittedType
        inferred: dynamic
  returnType: void
''');
  }

  test_inferType_function_returnType() async {
    await _assertIntrospectText('foo', r'''
foo() => 0;
''', r'''
foo
  flags: hasBody
  returnType: OmittedType
    inferred: dynamic
''');
  }

  test_inferType_getterInstance_returnType_fromSuper() async {
    await _assertIntrospectText('X', r'''
class A {
  int get foo => 0;
}

class X extends A {
  get foo => 0;
}
''', r'''
class X
  superclass: A
  methods
    foo
      flags: hasBody isGetter
      returnType: OmittedType
        inferred: int
''');
  }

  test_inferType_getterStatic_returnType() async {
    await _assertIntrospectText('X', r'''
class X {
  static get foo => 0;
}
''', r'''
class X
  methods
    foo
      flags: hasBody hasStatic isGetter
      returnType: OmittedType
        inferred: dynamic
''');
  }

  test_inferType_methodInstance_formalParameter_fromSuper() async {
    await _assertIntrospectText('X', r'''
class A {
  void foo(int a) {}
}

class X extends A {
  void foo(a) {}
}
''', r'''
class X
  superclass: A
  methods
    foo
      flags: hasBody
      positionalParameters
        a
          flags: isRequired
          type: OmittedType
            inferred: int
      returnType: void
''');
  }

  test_inferType_methodInstance_returnType_fromSuper() async {
    await _assertIntrospectText('X', r'''
class A {
  int foo() => 0;
}

class X extends A {
  foo() => 0;
}
''', r'''
class X
  superclass: A
  methods
    foo
      flags: hasBody
      returnType: OmittedType
        inferred: int
''');
  }

  test_inferType_methodStatic_formalParameter() async {
    await _assertIntrospectText('X', r'''
class X {
  static void foo(a) {}
}
''', r'''
class X
  methods
    foo
      flags: hasBody hasStatic
      positionalParameters
        a
          flags: isRequired
          type: OmittedType
            inferred: dynamic
      returnType: void
''');
  }

  test_inferType_methodStatic_returnType() async {
    await _assertIntrospectText('X', r'''
class X {
  static foo() => 0;
}
''', r'''
class X
  methods
    foo
      flags: hasBody hasStatic
      returnType: OmittedType
        inferred: dynamic
''');
  }

  test_inferType_setterInstance_formalParameter_fromSuper() async {
    await _assertIntrospectText('X', r'''
abstract class A {
  set foo(int a);
}

class X extends A {
  void set foo(a) {}
}
''', r'''
class X
  superclass: A
  methods
    foo
      flags: hasBody isSetter
      positionalParameters
        a
          flags: isRequired
          type: OmittedType
            inferred: int
      returnType: void
''');
  }

  test_inferType_setterInstance_returnType() async {
    await _assertIntrospectText('X', r'''
class X {
  set foo(int a) {}
}
''', r'''
class X
  methods
    foo
      flags: hasBody isSetter
      positionalParameters
        a
          flags: isRequired
          type: int
      returnType: OmittedType
        inferred: void
''');
  }

  test_inferType_setterStatic_formalParameter() async {
    await _assertIntrospectText('X', r'''
class X {
  static void set foo(a) {}
}
''', r'''
class X
  methods
    foo
      flags: hasBody hasStatic isSetter
      positionalParameters
        a
          flags: isRequired
          type: OmittedType
            inferred: dynamic
      returnType: void
''');
  }

  test_inferType_setterStatic_returnType() async {
    await _assertIntrospectText('X', r'''
class X {
  static set foo(int a) {}
}
''', r'''
class X
  methods
    foo
      flags: hasBody hasStatic isSetter
      positionalParameters
        a
          flags: isRequired
          type: int
      returnType: OmittedType
        inferred: void
''');
  }

  test_inferType_topGetter_returnType() async {
    await _assertIntrospectText('foo', r'''
get foo => 0;
''', r'''
foo
  flags: hasBody isGetter
  returnType: OmittedType
    inferred: dynamic
''');
  }

  test_inferType_topSetter_formalParameter() async {
    await _assertIntrospectText('foo=', r'''
void set foo(value) {}
''', r'''
foo
  flags: hasBody isSetter
  positionalParameters
    value
      flags: isRequired
      type: OmittedType
        inferred: dynamic
  returnType: void
''');
  }

  test_inferType_topSetter_returnType() async {
    await _assertIntrospectText('foo=', r'''
set foo(int value) {}
''', r'''
foo
  flags: hasBody isSetter
  positionalParameters
    value
      flags: isRequired
      type: int
  returnType: OmittedType
    inferred: void
''');
  }

  test_inferType_topVariable_fromInitializer() async {
    await _assertIntrospectText('foo', r'''
final foo = 0;
''', r'''
foo
  flags: hasFinal hasInitializer
  type: OmittedType
    inferred: int
''');
  }

  test_topLevelDeclarationsOf_imported_class() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {}
class B {}
''');

    await _assertLibraryDefinitionsPhaseText(
      'A',
      uriStr: 'package:test/a.dart',
      r'''
import 'a.dart';
''',
      r'''
topLevelDeclarationsOf
  class A
    superclass: Object
  class B
    superclass: Object
''',
    );
  }

  test_topLevelDeclarationsOf_self_class() async {
    await _assertLibraryDefinitionsPhaseText('A', r'''
class A {}
class B {}
''', r'''
topLevelDeclarationsOf
  class A
  class B
''');
  }

  test_topLevelDeclarationsOf_self_enum() async {
    await _assertLibraryDefinitionsPhaseText('A', r'''
enum A {v1}
enum B {v2}
''', r'''
topLevelDeclarationsOf
  enum A
    values
      v1
  enum B
    values
      v2
''');
  }

  test_topLevelDeclarationsOf_self_extension() async {
    await _assertLibraryDefinitionsPhaseText('A', r'''
extension A on int {}
extension B on double {}
''', r'''
topLevelDeclarationsOf
  extension A
    onType: int
  extension B
    onType: double
''');
  }

  test_topLevelDeclarationsOf_self_function() async {
    await _assertLibraryDefinitionsPhaseText('foo', r'''
void foo() {}
void bar() {}
''', r'''
topLevelDeclarationsOf
  foo
    flags: hasBody
    returnType: void
  bar
    flags: hasBody
    returnType: void
''');
  }

  test_topLevelDeclarationsOf_self_getter() async {
    await _assertLibraryDefinitionsPhaseText('foo', r'''
int get foo => 0;
int get bar => 0;
''', r'''
topLevelDeclarationsOf
  foo
    flags: hasBody isGetter
    returnType: int
  bar
    flags: hasBody isGetter
    returnType: int
''');
  }

  test_topLevelDeclarationsOf_self_mixin() async {
    await _assertLibraryDefinitionsPhaseText('A', r'''
mixin A {}
mixin B {}
''', r'''
topLevelDeclarationsOf
  mixin A
  mixin B
''');
  }

  test_topLevelDeclarationsOf_self_setter() async {
    await _assertLibraryDefinitionsPhaseText('foo=', r'''
set foo(int value) {}
set bar(int value) {}
''', r'''
topLevelDeclarationsOf
  foo
    flags: hasBody isSetter
    positionalParameters
      value
        flags: isRequired
        type: int
    returnType: OmittedType
      inferred: void
  bar
    flags: hasBody isSetter
    positionalParameters
      value
        flags: isRequired
        type: int
    returnType: OmittedType
      inferred: void
''');
  }

  test_topLevelDeclarationsOf_self_variable() async {
    await _assertLibraryDefinitionsPhaseText('foo', r'''
final int foo = 0;
final int bar = 0;
''', r'''
topLevelDeclarationsOf
  foo
    flags: hasFinal hasInitializer
    type: int
  bar
    flags: hasFinal hasInitializer
    type: int
''');
  }

  /// The [name] should be the name of a declaration in [code].
  Future<void> _assertIntrospectText(
    String name,
    String code,
    String expected,
  ) async {
    newFile(
      '$testPackageLibPath/introspect.dart',
      _getMacroCode('introspect.dart'),
    );

    await _assertIntrospectDefinitionText(
      '''
import 'introspect.dart';
$code
''',
      expected,
      name: name,
      uriStr: 'package:test/test.dart',
      withUnnamedConstructor: false,
    );
  }

  /// We use [nameToFind] only because there is no API to get `Library` by
  /// its URI. So, we get the identifier, resolve it to the declaration,
  /// and then get its `Library`.
  Future<void> _assertLibraryDefinitionsPhaseText(
    String nameToFind,
    String code,
    String expected, {
    String uriStr = 'package:test/test.dart',
  }) async {
    newFile(
      '$testPackageLibPath/introspect.dart',
      _getMacroCode('introspect.dart'),
    );

    var library = await buildLibrary('''
import 'introspect.dart';
$code

@LibraryTopLevelDeclarations(
  uriStr: '$uriStr',
  nameToFind: '$nameToFind',
)
void _starter() {}
''');

    _assertDefinitionsPhaseText(library, expected);
  }
}

@reflectiveTest
class MacroIntrospectNodeTest extends MacroElementsBaseTest {
  @override
  bool get keepLinkingLibraries => true;

  test_class_appendInterfaces() async {
    await _assertIntrospectText(r'''
import 'append.dart';

class A {}

@Introspect()
@AppendInterface('{{package:test/test.dart@A}}')
class X {}
''', r'''
class X
  interfaces
    A
''');
  }

  test_class_appendMixins() async {
    await _assertIntrospectText(r'''
import 'append.dart';

mixin A {}

@Introspect()
@AppendMixin('{{package:test/test.dart@A}}')
class X {}
''', r'''
class X
  mixins
    A
''');
  }

  test_class_constructor_flags_isFactory() async {
    await _assertIntrospectText(r'''
class A {
  A();

  @Introspect()
  factory A.named() => A();
}
''', r'''
named
  flags: hasBody hasStatic isFactory
  returnType: A
''');
  }

  test_class_constructor_metadata() async {
    await _assertIntrospectText(r'''
class A {
  @Introspect(
    withMetadata: true,
    withUnnamedConstructor: true,
  )
  @a1
  @a2
  A();
}

const a1 = 0;
const a2 = 0;
''', r'''
<unnamed>
  flags: hasStatic
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    IdentifierMetadataAnnotation
      identifier: a1
    IdentifierMetadataAnnotation
      identifier: a2
  returnType: A
''');
  }

  test_class_constructor_named() async {
    await _assertIntrospectText(r'''
class A {
  @Introspect()
  A.named();
}
''', r'''
named
  flags: hasStatic
  returnType: A
''');
  }

  test_class_constructor_namedParameters() async {
    await _assertIntrospectText(r'''
class A {
  @Introspect()
  A({required int a, String? b});
}
''', r'''
<unnamed>
  flags: hasStatic
  namedParameters
    a
      flags: isNamed isRequired
      type: int
    b
      flags: isNamed
      type: String?
  returnType: A
''');
  }

  test_class_constructor_positionalParameters() async {
    await _assertIntrospectText(r'''
class A {
  @Introspect()
  A(int a, [String? b]);
}
''', r'''
<unnamed>
  flags: hasStatic
  positionalParameters
    a
      flags: isRequired
      type: int
    b
      type: String?
  returnType: A
''');
  }

  test_class_constructor_positionalParameters_super() async {
    await _assertIntrospectText(r'''
import 'package:json/json.dart';

class A {
  final int f1;
  Point(this.foo);
}

class B extends A {
  @Introspect()
  B(super.f1);
}
''', r'''
<unnamed>
  flags: hasStatic
  positionalParameters
    f1
      flags: isRequired
      type: OmittedType
  returnType: B
''');
  }

  test_class_constructor_positionalParameters_super_typed() async {
    await _assertIntrospectText(r'''
import 'package:json/json.dart';

class A {
  final int f1;
  Point(this.foo);
}

class B extends A {
  @Introspect()
  B(int super.f1);
}
''', r'''
<unnamed>
  flags: hasStatic
  positionalParameters
    f1
      flags: isRequired
      type: int
  returnType: B
''');
  }

  test_class_constructor_positionalParameters_this() async {
    await _assertIntrospectText(r'''
import 'package:json/json.dart';

class A {
  final int f1;
  @Introspect()
  Point(this.foo);
}
''', r'''
Point
  positionalParameters
    foo
      flags: isRequired
      type: OmittedType
  returnType: OmittedType
''');
  }

  test_class_constructor_unnamed() async {
    await _assertIntrospectText(r'''
class A {
  @Introspect()
  A();
}
''', r'''
<unnamed>
  flags: hasStatic
  returnType: A
''');
  }

  test_class_extendsType() async {
    await _assertIntrospectText(r'''
import 'append.dart';

class A<T> {}

@Introspect()
@SetExtendsType('{{package:test/test.dart@A}}', ['{{dart:core@int}}'])
class X {}
''', r'''
class X
  superclass: A<int>
''');
  }

  test_class_field_flags_hasConst_true() async {
    await _assertIntrospectText(r'''
class X {
  @Introspect()
  static const int foo = 0;
}
''', r'''
foo
  flags: hasConst hasInitializer hasStatic
  type: int
''');
  }

  test_class_field_flags_hasExternal() async {
    await _assertIntrospectText(r'''
class X {
  @Introspect()
  external int foo;
}
''', r'''
foo
  flags: hasExternal
  type: int
''');
  }

  test_class_field_flags_hasFinal_false() async {
    await _assertIntrospectText(r'''
class X {
  @Introspect()
  int foo = 0;
}
''', r'''
foo
  flags: hasInitializer
  type: int
''');
  }

  test_class_field_flags_hasFinal_true() async {
    await _assertIntrospectText(r'''
class X {
  @Introspect()
  final int foo = 0;
}
''', r'''
foo
  flags: hasFinal hasInitializer
  type: int
''');
  }

  test_class_field_flags_hasInitializer_false() async {
    await _assertIntrospectText(r'''
class X {
  @Introspect()
  int? foo;
}
''', r'''
foo
  type: int?
''');
  }

  test_class_field_flags_hasLate() async {
    await _assertIntrospectText(r'''
class X {
  @Introspect()
  late int foo;
}
''', r'''
foo
  flags: hasLate
  type: int
''');
  }

  test_class_field_flags_hasStatic() async {
    await _assertIntrospectText(r'''
class X {
  @Introspect()
  static int foo = 0;
}
''', r'''
foo
  flags: hasInitializer hasStatic
  type: int
''');
  }

  test_class_field_type_explicit() async {
    await _assertIntrospectText(r'''
class X {
  @Introspect()
  int foo = 0;
}
''', r'''
foo
  flags: hasInitializer
  type: int
''');
  }

  test_class_field_type_implicit() async {
    await _assertIntrospectText(r'''
class X {
  @Introspect()
  final foo = 0;
}
''', r'''
foo
  flags: hasFinal hasInitializer
  type: OmittedType
''');
  }

  test_class_fields() async {
    await _assertIntrospectText(r'''
@Introspect()
class X {
  final int foo = 0;
  String bar = '';
}
''', r'''
class X
  fields
    foo
      flags: hasFinal hasInitializer
      type: int
    bar
      flags: hasInitializer
      type: String
''');
  }

  test_class_flags_hasAbstract() async {
    await _assertIntrospectText(r'''
@Introspect()
abstract class A {}
''', r'''
class A
  flags: hasAbstract
''');
  }

  test_class_getter() async {
    await _assertIntrospectText(r'''
abstract class A {
  @Introspect()
  int get foo => 0;
}
''', r'''
foo
  flags: hasBody isGetter
  returnType: int
''');
  }

  test_class_interfaces() async {
    await _assertIntrospectText(r'''
@Introspect()
class A implements B, C<int, String> {}
''', r'''
class A
  interfaces
    B
      noDeclaration
    C<int, String>
      noDeclaration
''');
  }

  test_class_metadata_constructor_named() async {
    await _assertIntrospectText(r'''
@Introspect(withMetadata: true)
@A.named()
class X {}

class A {
  const A.named()
}
''', r'''
class X
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    ConstructorMetadataAnnotation
      type: A
      constructorName: named
''');
  }

  test_class_metadata_constructor_named_imported() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A.named()
}
''');

    await _assertIntrospectText(r'''
import 'a.dart';

@Introspect(withMetadata: true)
@A.named()
class X {}

''', r'''
class X
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    ConstructorMetadataAnnotation
      type: A
      constructorName: named
''');
  }

  test_class_metadata_constructor_named_imported_withPrefix() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A.named()
}
''');

    await _assertIntrospectText(r'''
import 'a.dart' as prefix;

@Introspect(withMetadata: true)
@prefix.A.named()
class X {}

''', r'''
class X
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    ConstructorMetadataAnnotation
      type: A
      constructorName: named
''');
  }

  test_class_metadata_constructor_namedArguments() async {
    await _assertIntrospectText(r'''
@Introspect(withMetadata: true)
@A(a: 42, b: 'foo')
class X {}

class A {
  const A({int? a, String? b});
}
''', r'''
class X
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    ConstructorMetadataAnnotation
      type: A
      namedArguments
        a: [42]
        b: ['foo']
''');
  }

  test_class_metadata_constructor_positionalArguments() async {
    await _assertIntrospectText(r'''
@Introspect(withMetadata: true)
@A(42, 'foo')
class X {}

class A {
  const A(int a, String b);
}
''', r'''
class X
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    ConstructorMetadataAnnotation
      type: A
      positionalArguments
        [42]
        ['foo']
''');
  }

  test_class_metadata_constructor_unnamed() async {
    await _assertIntrospectText(r'''
@Introspect(withMetadata: true)
@A()
class X {}

class A {
  const A()
}
''', r'''
class X
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    ConstructorMetadataAnnotation
      type: A
''');
  }

  test_class_metadata_constructor_unnamed_imported() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A()
}
''');

    await _assertIntrospectText(r'''
import 'a.dart';

@Introspect(withMetadata: true)
@A()
class X {}

''', r'''
class X
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    ConstructorMetadataAnnotation
      type: A
''');
  }

  test_class_metadata_constructor_unnamed_imported_withPrefix() async {
    newFile('$testPackageLibPath/a.dart', r'''
class A {
  const A()
}
''');

    await _assertIntrospectText(r'''
import 'a.dart' as prefix;

@Introspect(withMetadata: true)
@prefix.A()
class X {}

''', r'''
class X
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    ConstructorMetadataAnnotation
      type: A
''');
  }

  test_class_metadata_identifier() async {
    await _assertIntrospectText(r'''
@Introspect(withMetadata: true)
@a1
@a2
class X {}

const a1 = 0;
const a2 = 0;
''', r'''
class X
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    IdentifierMetadataAnnotation
      identifier: a1
    IdentifierMetadataAnnotation
      identifier: a2
''');
  }

  test_class_metadata_identifier_imported() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a1 = 0;
const a2 = 0;
''');

    await _assertIntrospectText(r'''
import 'a.dart';

@Introspect(withMetadata: true)
@a1
@a2
class X {}

''', r'''
class X
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    IdentifierMetadataAnnotation
      identifier: a1
    IdentifierMetadataAnnotation
      identifier: a2
''');
  }

  test_class_metadata_identifier_imported_withPrefix() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a1 = 0;
const a2 = 0;
''');

    await _assertIntrospectText(r'''
import 'a.dart' as prefix;

@Introspect(withMetadata: true)
@prefix.a1
@prefix.a2
class X {}

''', r'''
class X
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    IdentifierMetadataAnnotation
      identifier: a1
    IdentifierMetadataAnnotation
      identifier: a2
''');
  }

  test_class_method_flags_hasBody_false() async {
    await _assertIntrospectText(r'''
abstract class A {
  @Introspect()
  void foo();
}
''', r'''
foo
  returnType: void
''');
  }

  test_class_method_flags_hasExternal() async {
    await _assertIntrospectText(r'''
abstract class A {
  @Introspect()
  external void foo();
}
''', r'''
foo
  flags: hasExternal
  returnType: void
''');
  }

  test_class_method_flags_hasStatic() async {
    await _assertIntrospectText(r'''
class A {
  @Introspect()
  static void foo() {}
}
''', r'''
foo
  flags: hasBody hasStatic
  returnType: void
''');
  }

  test_class_method_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    await _assertIntrospectText(r'''
import 'a.dart';

class X {
  @Introspect(withMetadata: true)
  @a
  void foo() {}
}

''', r'''
foo
  flags: hasBody
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    IdentifierMetadataAnnotation
      identifier: a
  returnType: void
''');
  }

  test_class_method_namedParameters() async {
    await _assertIntrospectText(r'''
abstract class A {
  @Introspect()
  void foo({required int a, String? b}) {}
}
''', r'''
foo
  flags: hasBody
  namedParameters
    a
      flags: isNamed isRequired
      type: int
    b
      flags: isNamed
      type: String?
  returnType: void
''');
  }

  test_class_method_namedParameters_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    await _assertIntrospectText(r'''
import 'a.dart';

abstract class A {
  @Introspect(withMetadata: true)
  void foo({@a required int x}) {}
}
''', r'''
foo
  flags: hasBody
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
  namedParameters
    x
      flags: isNamed isRequired
      metadata
        IdentifierMetadataAnnotation
          identifier: a
      type: int
  returnType: void
''');
  }

  test_class_method_positionalParameters() async {
    await _assertIntrospectText(r'''
abstract class A {
  @Introspect()
  void foo(int a, [String? b]) {}
}
''', r'''
foo
  flags: hasBody
  positionalParameters
    a
      flags: isRequired
      type: int
    b
      type: String?
  returnType: void
''');
  }

  test_class_method_positionalParameters_metadata() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    await _assertIntrospectText(r'''
import 'a.dart';

abstract class A {
  @Introspect(withMetadata: true)
  void foo(@a int x) {}
}
''', r'''
foo
  flags: hasBody
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
  positionalParameters
    x
      flags: isRequired
      metadata
        IdentifierMetadataAnnotation
          identifier: a
      type: int
  returnType: void
''');
  }

  test_class_mixins() async {
    await _assertIntrospectText(r'''
@Introspect()
class A with B, C<int, String> {}
''', r'''
class A
  mixins
    B
      noDeclaration
    C<int, String>
      noDeclaration
''');
  }

  test_class_setter() async {
    await _assertIntrospectText(r'''
abstract class A {
  @Introspect()
  set foo(int value) {}
}
''', r'''
foo
  flags: hasBody isSetter
  positionalParameters
    value
      flags: isRequired
      type: int
  returnType: OmittedType
''');
  }

  test_class_superclass() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B {}
''', r'''
class A
  superclass: B
    noDeclaration
''');
  }

  test_class_superclass_nullable() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B<int?> {}
''', r'''
class A
  superclass: B<int?>
    noDeclaration
''');
  }

  test_class_superclass_typeArguments() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B<String, List<int>> {}
''', r'''
class A
  superclass: B<String, List<int>>
    noDeclaration
''');
  }

  test_class_superclassOf() async {
    await _assertIntrospectText(r'''
class A {}

@Introspect(
  withDetailsFor: {'A'},
)
class X extends A {}
''', r'''
class X
  superclass: A
    class A
''');
  }

  test_class_superclassOf_implicit() async {
    await _assertIntrospectText(r'''
@Introspect()
class X {}
''', r'''
class X
''');
  }

  test_class_superclassOf_unresolved() async {
    await _assertIntrospectText(r'''
@Introspect()
class X extends A {}
''', r'''
class X
  superclass: A
    noDeclaration
''');
  }

  test_class_typeParameter_metadata_identifier_imported() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    await _assertIntrospectText(r'''
import 'a.dart';

@Introspect(withMetadata: true)
class A<@a T> {}
''', r'''
class A
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
  typeParameters
    T
      metadata
        IdentifierMetadataAnnotation
          identifier: a
''');
  }

  test_class_typeParameters() async {
    await _assertIntrospectText(r'''
@Introspect()
class A<T, U extends List<T>> {}
''', r'''
class A
  typeParameters
    T
    U
      bound: List<T>
''');
  }

  test_classAlias_flags_hasAbstract() async {
    await _assertIntrospectText(r'''
class A {}
mixin M {}

@Introspect()
abstract class C = A with M;
''', r'''
class C
  flags: hasAbstract
  superclass: A
  mixins
    M
''');
  }

  test_classAlias_interfaces() async {
    await _assertIntrospectText(r'''
class A {}
mixin M {}
class I {}
class J {}

@Introspect()
class C = A with M implements I, J;
''', r'''
class C
  superclass: A
  mixins
    M
  interfaces
    I
    J
''');
  }

  test_classAlias_metadata_identifier() async {
    await _assertIntrospectText(r'''
class A {}
mixin M {}

@Introspect(withMetadata: true)
@a1
@a2
class C = A with M;

class X {}
''', r'''
class C
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    IdentifierMetadataAnnotation
      identifier: a1
    IdentifierMetadataAnnotation
      identifier: a2
  superclass: A
  mixins
    M
''');
  }

  test_classAlias_typeParameters() async {
    await _assertIntrospectText(r'''
class A<T1> {}
mixin M<U1> {}

@Introspect()
class C<T2, U2> = A<T2> with M<U2>;
''', r'''
class C
  superclass: A<T2>
  typeParameters
    T2
    U2
  mixins
    M<U2>
''');
  }

  test_enum_fields() async {
    await _assertIntrospectText(r'''
@Introspect()
enum A {
  v(0);
  final int foo;
  const A(this.foo);
}
''', r'''
enum A
  values
    v
  fields
    foo
      flags: hasFinal
      type: int
''');
  }

  test_enum_getters() async {
    await _assertIntrospectText(r'''
@Introspect()
enum A {
  v;
  int get foo => 0;
}
''', r'''
enum A
  values
    v
  methods
    foo
      flags: hasBody isGetter
      returnType: int
''');
  }

  test_enum_interfaces() async {
    await _assertIntrospectText(r'''
class A {}
class B {}

@Introspect()
enum X implements A, B {
  v
}
''', r'''
enum X
  interfaces
    A
    B
  values
    v
''');
  }

  test_enum_metadata_identifier_imported() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    await _assertIntrospectText(r'''
import 'a.dart';

@Introspect(withMetadata: true)
@a
enum X {
  v
}

''', r'''
enum X
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    IdentifierMetadataAnnotation
      identifier: a
  values
    v
''');
  }

  test_enum_method() async {
    await _assertIntrospectText(r'''
enum A {
  v;
  @Introspect()
  void foo() {}
}
''', r'''
foo
  flags: hasBody
  returnType: void
''');
  }

  test_enum_methods() async {
    await _assertIntrospectText(r'''
@Introspect()
enum A {
  v;
  void foo() {}
}
''', r'''
enum A
  values
    v
  methods
    foo
      flags: hasBody
      returnType: void
''');
  }

  test_enum_mixins() async {
    await _assertIntrospectText(r'''
mixin A {}
mixin B {}

@Introspect()
enum X with A, B {
  v
}
''', r'''
enum X
  mixins
    A
    B
  values
    v
''');
  }

  test_enum_setters() async {
    await _assertIntrospectText(r'''
@Introspect()
enum A {
  v;
  set foo(int value) {}
}
''', r'''
enum A
  values
    v
  methods
    foo
      flags: hasBody isSetter
      positionalParameters
        value
          flags: isRequired
          type: int
      returnType: OmittedType
''');
  }

  test_enum_typeParameters() async {
    await _assertIntrospectText(r'''
@Introspect()
enum E<T> {
  v
}
''', r'''
enum E
  typeParameters
    T
  values
    v
''');
  }

  test_enum_values() async {
    await _assertIntrospectText(r'''
@Introspect()
enum A {
  foo, bar
}
''', r'''
enum A
  values
    foo
    bar
''');
  }

  test_enumValue() async {
    await _assertIntrospectText(r'''
enum A {
  @Introspect()
  foo;
}
''', r'''
foo
''');
  }

  test_enumValue_metadata_identifier_imported() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    await _assertIntrospectText(r'''
import 'a.dart';

enum X {
  @Introspect(withMetadata: true)
  @a
  v
}

''', r'''
v
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    IdentifierMetadataAnnotation
      identifier: a
''');
  }

  test_extension_getter() async {
    await _assertIntrospectText(r'''
extension A on int {
  @Introspect()
  int get foo => 0;
}
''', r'''
foo
  flags: hasBody isGetter
  returnType: int
''');
  }

  test_extension_getters() async {
    await _assertIntrospectText(r'''
@Introspect()
extension A on int {
  int get foo => 0;
}
''', r'''
extension A
  onType: int
  methods
    foo
      flags: hasBody isGetter
      returnType: int
''');
  }

  test_extension_metadata_identifier() async {
    await _assertIntrospectText(r'''
const a = 0;

@Introspect(withMetadata: true)
@a
extension A on int {}
''', r'''
extension A
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    IdentifierMetadataAnnotation
      identifier: a
  onType: int
''');
  }

  test_extension_method() async {
    await _assertIntrospectText(r'''
extension A on int {
  @Introspect()
  void foo() {}
}
''', r'''
foo
  flags: hasBody
  returnType: void
''');
  }

  test_extension_methods() async {
    await _assertIntrospectText(r'''
@Introspect()
extension A on int {
  void foo() {}
}
''', r'''
extension A
  onType: int
  methods
    foo
      flags: hasBody
      returnType: void
''');
  }

  test_extension_typeParameters() async {
    await _assertIntrospectText(r'''
@Introspect()
extension A<T> on int {}
''', r'''
extension A
  typeParameters
    T
  onType: int
''');
  }

  test_extensionType_getter() async {
    await _assertIntrospectText(r'''
extension type A(int it) {
  @Introspect()
  int get foo => 0;
}
''', r'''
foo
  flags: hasBody isGetter
  returnType: int
''');
  }

  test_extensionType_getters() async {
    await _assertIntrospectText(r'''
@Introspect()
extension type A(int it) {
  int get foo => 0;
}
''', r'''
extension type A
  representationType: int
  fields
    it
      flags: hasFinal
      type: int
  methods
    foo
      flags: hasBody isGetter
      returnType: int
''');
  }

  test_extensionType_metadata_identifier() async {
    await _assertIntrospectText(r'''
const a = 0;

@Introspect(withMetadata: true)
@a
extension type A(int it) {}
''', r'''
extension type A
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    IdentifierMetadataAnnotation
      identifier: a
  representationType: int
  fields
    it
      flags: hasFinal
      type: int
''');
  }

  test_extensionType_method() async {
    await _assertIntrospectText(r'''
extension type A(int it) {
  @Introspect()
  void foo() {}
}
''', r'''
foo
  flags: hasBody
  returnType: void
''');
  }

  test_extensionType_methods() async {
    await _assertIntrospectText(r'''
@Introspect()
extension type A(int it) {
  void foo() {}
}
''', r'''
extension type A
  representationType: int
  fields
    it
      flags: hasFinal
      type: int
  methods
    foo
      flags: hasBody
      returnType: void
''');
  }

  test_extensionType_typeParameters() async {
    await _assertIntrospectText(r'''
@Introspect()
extension type A<T>(int it) {}
''', r'''
extension type A
  typeParameters
    T
  representationType: int
  fields
    it
      flags: hasFinal
      type: int
''');
  }

  test_functionType_typeParameters() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B<void Function<T, U extends num>()> {}
''', r'''
class A
  superclass: B<void Function<T, U extends num>()>
    noDeclaration
''');
  }

  test_functionTypeAnnotation_formalParameters_namedOptional_simpleFormalParameter() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B<void Function(int a, {int? b, int? c})> {}
''', r'''
class A
  superclass: B<void Function(int a, {int? b}, {int? c})>
    noDeclaration
''');
  }

  test_functionTypeAnnotation_formalParameters_namedRequired_simpleFormalParameter() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B<void Function(int a, {required int b, required int c})> {}
''', r'''
class A
  superclass: B<void Function(int a, {required int b}, {required int c})>
    noDeclaration
''');
  }

  test_functionTypeAnnotation_formalParameters_positionalOptional_simpleFormalParameter() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B<void Function(int a, [int b, int c])> {}
''', r'''
class A
  superclass: B<void Function(int a, [int b], [int c])>
    noDeclaration
''');
  }

  test_functionTypeAnnotation_formalParameters_positionalOptional_simpleFormalParameter_noName() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B<void Function(int a, [int, int])> {}
''', r'''
class A
  superclass: B<void Function(int a, [int], [int])>
    noDeclaration
''');
  }

  test_functionTypeAnnotation_formalParameters_positionalRequired_simpleFormalParameter() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B<void Function(int a, double b)> {}
''', r'''
class A
  superclass: B<void Function(int a, double b)>
    noDeclaration
''');
  }

  test_functionTypeAnnotation_formalParameters_positionalRequired_simpleFormalParameter_noName() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B<void Function(int, double)> {}
''', r'''
class A
  superclass: B<void Function(int, double)>
    noDeclaration
''');
  }

  test_functionTypeAnnotation_nullable() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B<void Function()?> {}
''', r'''
class A
  superclass: B<void Function()?>
    noDeclaration
''');
  }

  test_functionTypeAnnotation_returnType() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B<void Function()> {}
''', r'''
class A
  superclass: B<void Function()>
    noDeclaration
''');
  }

  test_functionTypeAnnotation_returnType_omitted() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B<Function()> {}
''', r'''
class A
  superclass: B<OmittedType Function()>
    noDeclaration
''');
  }

  test_functionTypeAnnotation_typeParameters() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends B<void Function<T, U extends num>()> {}
''', r'''
class A
  superclass: B<void Function<T, U extends num>()>
    noDeclaration
''');
  }

  test_library_classes() async {
    await _assertIntrospectText(r'''
@Introspect()
library;

class A {
  void foo() {}
}

class B {
  void bar() {}
}
''', r'''
class A
  methods
    foo
      flags: hasBody
      returnType: void
class B
  methods
    bar
      flags: hasBody
      returnType: void
''');
  }

  test_library_extensions() async {
    await _assertIntrospectText(r'''
@Introspect()
library;

extension A on int {
  void foo() {}
}

extension B on int {
  void bar() {}
}
''', r'''
extension A
  onType: int
  methods
    foo
      flags: hasBody
      returnType: void
extension B
  onType: int
  methods
    bar
      flags: hasBody
      returnType: void
''');
  }

  test_library_extensionTypes() async {
    await _assertIntrospectText(r'''
@Introspect()
library;

extension type A(int it) {
  void foo() {}
}
''', r'''
extension type A
  representationType: int
  fields
    it
      flags: hasFinal
      type: int
  methods
    foo
      flags: hasBody
      returnType: void
''');
  }

  test_library_mixin() async {
    await _assertIntrospectText(r'''
@Introspect()
library;

mixin A {
  void foo() {}
}

mixin B {
  void bar() {}
}
''', r'''
mixin A
  methods
    foo
      flags: hasBody
      returnType: void
mixin B
  methods
    bar
      flags: hasBody
      returnType: void
''');
  }

  test_mixin_appendInterfaces() async {
    await _assertIntrospectText(r'''
import 'append.dart';

class A {}

@Introspect()
@AppendInterface('{{package:test/test.dart@A}}')
mixin X {}
''', r'''
mixin X
  interfaces
    A
''');
  }

  test_mixin_fields() async {
    await _assertIntrospectText(r'''
@Introspect()
mixin X {
  final int foo = 0;
  String bar = '';
}
''', r'''
mixin X
  fields
    foo
      flags: hasFinal hasInitializer
      type: int
    bar
      flags: hasInitializer
      type: String
''');
  }

  test_mixin_flags_hasBase() async {
    await _assertIntrospectText(r'''
@Introspect()
base mixin A {}
''', r'''
mixin A
  flags: hasBase
''');
  }

  test_mixin_getter() async {
    await _assertIntrospectText(r'''
mixin A {
  @Introspect()
  int get foo => 0;
}
''', r'''
foo
  flags: hasBody isGetter
  returnType: int
''');
  }

  test_mixin_interfaces() async {
    await _assertIntrospectText(r'''
@Introspect()
mixin A implements B, C {}
''', r'''
mixin A
  interfaces
    B
      noDeclaration
    C
      noDeclaration
''');
  }

  test_mixin_metadata_identifier_imported() async {
    newFile('$testPackageLibPath/a.dart', r'''
const a = 0;
''');

    await _assertIntrospectText(r'''
import 'a.dart';

@Introspect(withMetadata: true)
@a
mixin X {}

''', r'''
mixin X
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    IdentifierMetadataAnnotation
      identifier: a
''');
  }

  test_mixin_method() async {
    await _assertIntrospectText(r'''
mixin A {
  @Introspect()
  void foo() {}
}
''', r'''
foo
  flags: hasBody
  returnType: void
''');
  }

  test_mixin_setter() async {
    await _assertIntrospectText(r'''
mixin A {
  @Introspect()
  set foo(int value) {}
}
''', r'''
foo
  flags: hasBody isSetter
  positionalParameters
    value
      flags: isRequired
      type: int
  returnType: OmittedType
''');
  }

  test_mixin_superclassConstraints() async {
    await _assertIntrospectText(r'''
@Introspect()
mixin A on B, C {}
''', r'''
mixin A
  superclassConstraints
    B
      noDeclaration
    C
      noDeclaration
''');
  }

  test_mixin_typeParameters() async {
    await _assertIntrospectText(r'''
@Introspect()
mixin A<T, U extends List<T>> {}
''', r'''
mixin A
  typeParameters
    T
    U
      bound: List<T>
''');
  }

  test_namedTypeAnnotation_prefixed() async {
    await _assertIntrospectText(r'''
@Introspect()
class A extends prefix.B {}
''', r'''
class A
  superclass: B
    noDeclaration
''');
  }

  test_namedTypeAnnotation_typeArguments_absent() async {
    await _assertIntrospectText(r'''
@Introspect()
Map get foo => {};
''', r'''
foo
  flags: hasBody isGetter
  returnType: Map
''');
  }

  test_namedTypeAnnotation_typeArguments_wrongCount() async {
    await _assertIntrospectText(r'''
@Introspect()
Map<int> get foo => {};
''', r'''
foo
  flags: hasBody isGetter
  returnType: Map<int>
''');
  }

  test_typeAlias_namedType() async {
    await _assertIntrospectText(r'''
@Introspect()
typedef X = List<int>;
''', r'''
typedef X
  aliasedType: List<int>
''');
  }

  test_unit_function() async {
    await _assertIntrospectText(r'''
@Introspect()
void foo() {}
''', r'''
foo
  flags: hasBody
  returnType: void
''');
  }

  test_unit_function_flags_hasExternal() async {
    await _assertIntrospectText(r'''
@Introspect()
external void foo();
''', r'''
foo
  flags: hasExternal
  returnType: void
''');
  }

  test_unit_function_metadata() async {
    await _assertIntrospectText(r'''
@Introspect(withMetadata: true)
@a1
@a2
void foo() {}

const a1 = 0;
const a2 = 0;
''', r'''
foo
  flags: hasBody
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    IdentifierMetadataAnnotation
      identifier: a1
    IdentifierMetadataAnnotation
      identifier: a2
  returnType: void
''');
  }

  test_unit_function_namedParameters() async {
    await _assertIntrospectText(r'''
@Introspect()
void foo({required int a, String? b}) {}
''', r'''
foo
  flags: hasBody
  namedParameters
    a
      flags: isNamed isRequired
      type: int
    b
      flags: isNamed
      type: String?
  returnType: void
''');
  }

  test_unit_function_positionalParameters() async {
    await _assertIntrospectText(r'''
@Introspect()
void foo(int a, [String? b]) {}
''', r'''
foo
  flags: hasBody
  positionalParameters
    a
      flags: isRequired
      type: int
    b
      type: String?
  returnType: void
''');
  }

  test_unit_getter() async {
    await _assertIntrospectText(r'''
@Introspect()
int get foo => 0;
''', r'''
foo
  flags: hasBody isGetter
  returnType: int
''');
  }

  test_unit_setter() async {
    await _assertIntrospectText(r'''
@Introspect()
set foo(int value) {}
''', r'''
foo
  flags: hasBody isSetter
  positionalParameters
    value
      flags: isRequired
      type: int
  returnType: OmittedType
''');
  }

  test_unit_variable_flags_hasConst_true() async {
    await _assertIntrospectText(r'''
@Introspect()
const foo = 0;
''', r'''
foo
  flags: hasConst hasInitializer
  type: OmittedType
''');
  }

  test_unit_variable_flags_hasExternal_true() async {
    await _assertIntrospectText(r'''
@Introspect()
external int foo;
''', r'''
foo
  flags: hasExternal
  type: int
''');
  }

  test_unit_variable_flags_hasFinal_false() async {
    await _assertIntrospectText(r'''
@Introspect()
var foo = 0;
''', r'''
foo
  flags: hasInitializer
  type: OmittedType
''');
  }

  test_unit_variable_flags_hasFinal_true() async {
    await _assertIntrospectText(r'''
@Introspect()
final foo = 0;
''', r'''
foo
  flags: hasFinal hasInitializer
  type: OmittedType
''');
  }

  test_unit_variable_flags_hasLate_true() async {
    await _assertIntrospectText(r'''
@Introspect()
late int foo;
''', r'''
foo
  flags: hasLate
  type: int
''');
  }

  test_unit_variable_metadata() async {
    await _assertIntrospectText(r'''
@Introspect(withMetadata: true)
@a1
@a2
final foo = 0;

const a1 = 0;
const a2 = 0;
''', r'''
foo
  flags: hasFinal hasInitializer
  metadata
    ConstructorMetadataAnnotation
      type: Introspect
    IdentifierMetadataAnnotation
      identifier: a1
    IdentifierMetadataAnnotation
      identifier: a2
  type: OmittedType
''');
  }

  test_unit_variable_type_explicit() async {
    await _assertIntrospectText(r'''
@Introspect()
final num foo = 0;
''', r'''
foo
  flags: hasFinal hasInitializer
  type: num
''');
  }

  test_unit_variable_type_implicit() async {
    await _assertIntrospectText(r'''
@Introspect()
final foo = 0;
''', r'''
foo
  flags: hasFinal hasInitializer
  type: OmittedType
''');
  }

  /// Assert that the textual dump of the introspection information produced
  /// by `IntrospectTypesPhaseMacro` in [code], is the [expected].
  Future<void> _assertIntrospectText(
    String code,
    String expected,
  ) async {
    var actual = await _getIntrospectText(code);
    if (actual != expected) {
      NodeTextExpectationsCollector.add(actual);
      print('-------- Actual --------');
      print('$actual------------------------');
    }
    expect(actual, expected);
  }

  /// The [code] should have exactly one application of `IntrospectMacro`.
  /// It may contain arbitrary code otherwise.
  ///
  /// The macro generates a top-level constant `_introspect`, with a string
  /// literal initializer - the textual dump of the introspection.
  Future<String> _getIntrospectText(String code) async {
    newFile(
      '$testPackageLibPath/introspect.dart',
      _getMacroCode('introspect.dart'),
    );

    var library = await buildLibrary('''
import 'introspect.dart';
$code
''');

    if (library.allMacroDiagnostics.isNotEmpty) {
      failWithLibraryText(library);
    }

    return library.topLevelElements
        .whereType<ConstTopLevelVariableElementImpl>()
        .where((e) => e.name == '_introspect')
        .map((e) => (e.constantInitializer as SimpleStringLiteral).value)
        .join('\n');
  }
}

@reflectiveTest
class MacroStaticTypeTest extends MacroElementsBaseTest {
  @override
  bool get keepLinkingLibraries => true;

  @override
  Future<void> setUp() async {
    await super.setUp();

    newFile(
      '$testPackageLibPath/static_type.dart',
      _getMacroCode('static_type.dart'),
    );
  }

  @TestTimeout(Timeout(Duration(seconds: 60)))
  test_isExactly() async {
    const testCases = {
      ('double', 'double', true),
      ('double', 'int', false),
      ('int', 'double', false),
      ('int', 'int', true),
      ('int', 'void', false),
      ('void', 'void', true),
      // Object
      ('Object?', 'Object?', true),
      ('Object?', 'Object', false),
      ('Object?', 'dynamic', false),
      // InterfaceType, type arguments
      ('List<int>', 'List<double>', false),
      ('List<int>', 'List<int>', true),
      // FunctionType
      //   returnType
      ('void Function()', 'void Function()', true),
      ('void Function()', 'int Function()', false),
      //   typeParameters
      ('void Function<T>()', 'void Function<T>()', true),
      ('void Function<T>()', 'void Function()', false),
      //   positionalParameters
      ('void Function(int a)', 'void Function(int a)', true),
      ('void Function(int a)', 'void Function(double a)', false),
      ('void Function([int a])', 'void Function([int a])', true),
      ('void Function([int a])', 'void Function(int a)', false),
      //   namedParameters
      ('void Function({int a})', 'void Function({int a})', true),
      ('void Function({int a})', 'void Function({double a})', false),
      (
        'void Function({required int a})',
        'void Function({required int a})',
        true,
      ),
      ('void Function({int a})', 'void Function({required int a})', false),
      // RecordType
      ('(int,)', '(int,)', true),
      ('(int,)', '(double,)', false),
      ('({int a,})', '({int a,})', true),
      ('({int a,})', '({int b,})', false),
      ('({int a,})', '({double a,})', false),
      ('({int a,})', '({int a, int b})', false),
    };

    for (var testCase in testCases) {
      await disposeAnalysisContextCollection();
      await _assertIsExactly(
        firstTypeCode: testCase.$1,
        secondTypeCode: testCase.$2,
        isExactly: testCase.$3,
      );
    }
  }

  /// Verify what happens when we use `RawTypeAnnotationCode`.
  /// We don't see it, because it disappears after the types phase.
  test_isExactly_class_asRawCode_same() async {
    var library = await buildLibrary('''
import 'append.dart';
import 'static_type.dart';

@DeclareClassAppendInterfaceRawCode('A')
class X {
  @IsExactly_enclosingClassInterface_formalParameterType()
  void foo(A a) {}
}
''');

    var generated = _getMacroGeneratedCode(library);
    _assertIsExactlyValue(generated, true);
  }

  test_isExactly_enum_notSame() async {
    await _assertIsExactly(
      firstTypeCode: 'A',
      secondTypeCode: 'B',
      isExactly: false,
      additionalDeclarations: r'''
enum A { v }
enum B { v }
''',
    );
  }

  test_isExactly_enum_same() async {
    await _assertIsExactly(
      firstTypeCode: 'A',
      secondTypeCode: 'A',
      isExactly: true,
      additionalDeclarations: r'''
enum A { v }
''',
    );
  }

  test_isExactly_extensionType_notSame() async {
    await _assertIsExactly(
      firstTypeCode: 'A',
      secondTypeCode: 'B',
      isExactly: false,
      additionalDeclarations: r'''
extension type A(int it) {}
extension type B(int it) {}
''',
    );
  }

  test_isExactly_extensionType_same() async {
    await _assertIsExactly(
      firstTypeCode: 'A',
      secondTypeCode: 'A',
      isExactly: true,
      additionalDeclarations: r'''
extension type A(int it) {}
''',
    );
  }

  test_isExactly_mixin_notSame() async {
    await _assertIsExactly(
      firstTypeCode: 'A',
      secondTypeCode: 'B',
      isExactly: false,
      additionalDeclarations: r'''
mixin A {}
mixin B {}
''',
    );
  }

  test_isExactly_mixin_same() async {
    await _assertIsExactly(
      firstTypeCode: 'A',
      secondTypeCode: 'A',
      isExactly: true,
      additionalDeclarations: r'''
mixin A {}
''',
    );
  }

  test_isExactly_namedTypeAnnotation_typeArguments_absent() async {
    await _assertIsExactly(
      firstTypeCode: 'Map',
      secondTypeCode: 'Map<dynamic, dynamic>',
      isExactly: true,
    );
  }

  test_isExactly_omittedType_notSame() async {
    var library = await buildLibrary('''
import 'static_type.dart';

class A {
  void foo(int a, double b) {}
}

class B extends A {
  @IsExactly()
  void foo(a, b) {}
}
''');

    var generated = _getMacroGeneratedCode(library);
    _assertIsExactlyValue(generated, false);
  }

  test_isExactly_omittedType_same() async {
    var library = await buildLibrary('''
import 'static_type.dart';

class A {
  void foo(int a, int b) {}
}

class B extends A {
  @IsExactly()
  void foo(a, b) {}
}
''');

    var generated = _getMacroGeneratedCode(library);
    _assertIsExactlyValue(generated, true);
  }

  test_isExactly_typeParameter_notSame() async {
    var library = await buildLibrary('''
import 'static_type.dart';

@IsExactly()
void foo<T, U>(T a, U b) {}
''');

    var generated = _getMacroGeneratedCode(library);
    _assertIsExactlyValue(generated, false);
  }

  test_isExactly_typeParameter_same() async {
    var library = await buildLibrary('''
import 'static_type.dart';

@IsExactly()
void foo<T>(T a, T b) {}
''');

    var generated = _getMacroGeneratedCode(library);
    _assertIsExactlyValue(generated, true);
  }

  test_isSubtype() async {
    const testCases = {
      ('double', 'double', true),
      ('double', 'num', true),
      ('double', 'int', false),
      ('double', 'Object', true),
      ('int', 'double', false),
      ('int', 'num', true),
      ('int', 'int', true),
      ('int', 'Object', true),
      // Object
      ('Object?', 'Object?', true),
      ('Object?', 'Object', false),
      ('Object', 'Object?', true),
      ('Object', 'Object', true),
      // InterfaceType, type arguments
      ('List<int>', 'List<double>', false),
      ('List<int>', 'List<num>', true),
      ('List<int>', 'List<int>', true),
      // FunctionType
      //   returnType
      ('void Function()', 'void Function()', true),
      ('int Function()', 'double Function()', false),
      ('int Function()', 'num Function()', true),
      ('int Function()', 'int Function()', true),
      // RecordType
      ('(int,)', '(double,)', false),
      ('(int,)', '(num,)', true),
      ('(int,)', '(int,)', true),
      ('({int a,})', '({double a,})', false),
      ('({int a,})', '({num a,})', true),
      ('({int a,})', '({int a,})', true),
      ('({int a,})', '({int b,})', false),
    };

    for (var testCase in testCases) {
      await disposeAnalysisContextCollection();
      await _assertIsSubtype(
        firstTypeCode: testCase.$1,
        secondTypeCode: testCase.$2,
        isSubtype: testCase.$3,
      );
    }
  }

  Future<void> _assertIsExactly({
    required String firstTypeCode,
    required String secondTypeCode,
    required bool isExactly,
    String additionalDeclarations = '',
  }) async {
    var library = await buildLibrary('''
import 'static_type.dart';

$additionalDeclarations

@IsExactly()
void foo($firstTypeCode a, $secondTypeCode b) {}
''');

    var generated = _getMacroGeneratedCode(library);
    var expected = _isExactlyExpected(isExactly);
    if (!generated.contains(expected)) {
      fail(
        '`$firstTypeCode` isExactly `$secondTypeCode`'
        ' expected to be `$isExactly`, but is not.\n',
      );
    }
  }

  void _assertIsExactlyValue(String generated, bool isExactly) {
    var expected = _isExactlyExpected(isExactly);
    expect(generated, contains(expected));
  }

  Future<void> _assertIsSubtype({
    required String firstTypeCode,
    required String secondTypeCode,
    required bool isSubtype,
    String additionalDeclarations = '',
  }) async {
    var library = await buildLibrary('''
import 'static_type.dart';

$additionalDeclarations

@IsSubtype()
void foo($firstTypeCode a, $secondTypeCode b) {}
''');

    var generated = _getMacroGeneratedCode(library);
    var expected = _isSubtypeExpected(isSubtype);
    if (!generated.contains(expected)) {
      fail(
        '`$firstTypeCode` isSubtype `$secondTypeCode`'
        ' expected to be `$isSubtype`, but is not.\n',
      );
    }
  }

  String _isExactlyExpected(bool isExactly) {
    return '=> $isExactly; // isExactly';
  }

  String _isSubtypeExpected(bool isSubtype) {
    return '=> $isSubtype; // isSubtype';
  }
}

abstract class MacroTypesTest extends MacroElementsBaseTest {
  final List<io.Directory> _ioDirectoriesToDelete = [];

  @override
  bool get retainDataForTesting => true;

  @override
  Future<void> tearDown() async {
    for (var directory in _ioDirectoriesToDelete) {
      try {
        directory.deleteSync(
          recursive: true,
        );
      } catch (_) {}
    }

    return super.tearDown();
  }

  test_application_newInstance_withoutPrefix() async {
    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareType('A', 'class MyClass {}')
class A {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/append.dart
  definingUnit
    reference: self
    classes
      class A @67
        reference: self::@class::A
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class MyClass {}
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          class MyClass @49
            reference: self::@augmentation::package:test/test.macro.dart::@class::MyClass
''');
  }

  test_application_newInstance_withoutPrefix_namedConstructor() async {
    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareType.named('A', 'class MyClass {}')
class A {}
''');

    configuration.withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @73
        constructors
          synthetic @-1
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class MyClass {}
---
      definingUnit
        classes
          class MyClass @49
            constructors
              synthetic @-1
''');
  }

  test_application_newInstance_withPrefix() async {
    var library = await buildLibrary(r'''
import 'append.dart' as prefix;

@prefix.DeclareType('A', 'class MyClass {}')
class A {}
''');

    configuration.withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart as prefix @24
  definingUnit
    classes
      class A @84
        constructors
          synthetic @-1
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class MyClass {}
---
      definingUnit
        classes
          class MyClass @49
            constructors
              synthetic @-1
''');
  }

  test_application_newInstance_withPrefix_namedConstructor() async {
    var library = await buildLibrary(r'''
import 'append.dart' as prefix;

@prefix.DeclareType.named('A', 'class MyClass {}')
class A {}
''');

    configuration.withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart as prefix @24
  definingUnit
    classes
      class A @90
        constructors
          synthetic @-1
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class MyClass {}
---
      definingUnit
        classes
          class MyClass @49
            constructors
              synthetic @-1
''');
  }

  test_declareType_exported() async {
    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareType('B', 'class B {}')
class A {}
''');

    configuration
      ..withConstructors = false
      ..withExportScope = true
      ..withMetadata = false
      ..withPropertyLinking = true
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/append.dart
  definingUnit
    reference: self
    classes
      class A @61
        reference: self::@class::A
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class B {}
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          class B @49
            reference: self::@augmentation::package:test/test.macro.dart::@class::B
  exportedReferences
    declared self::@augmentation::package:test/test.macro.dart::@class::B
    declared self::@class::A
  exportNamespace
    A: self::@class::A
    B: self::@augmentation::package:test/test.macro.dart::@class::B
''');
  }

  test_executable() async {
    // We use AOT executables only on Linux.
    if (resourceProvider.pathContext.style != package_path.Style.posix) {
      return;
    }

    // No need to verify reading elements for this test.
    if (!keepLinkingLibraries) {
      return;
    }

    const macroCode = r'''
import 'package:macros/macros.dart';

macro class MyMacro implements ClassTypesMacro {
  const MyMacro();

  buildTypesForClass(clazz, builder) async {
    builder.declareType(
      'MyClass',
      DeclarationCode.fromString('class MyClass {}'),
    );
  }
}
''';

    // Compile the macro to executable.
    io.File macroExecutable;
    {
      var macroMainContent = macro.bootstrapMacroIsolate(
        {
          'package:test/a.dart': {
            'MyMacro': ['']
          },
        },
        macro.SerializationMode.byteData,
      );

      var tempCompileDirectory =
          io.Directory.systemTemp.createTempSync('dartAnalyzerMacro');
      _ioDirectoriesToDelete.add(tempCompileDirectory);

      var fileSystem = PhysicalResourceProvider.INSTANCE;
      var compileRoot = fileSystem.getFolder(tempCompileDirectory.path);

      var testRoot = compileRoot.getChildAssumingFolder('test');
      testRoot.newFile('lib/a.dart').writeAsStringSync(macroCode);

      var testBin = testRoot.getChildAssumingFolder('bin');
      var testMain = testBin.newFile('main.dart');
      testMain.writeAsStringSync(macroMainContent);

      MacrosEnvironment.instance.privateMacrosFolder.copyTo(compileRoot);
      MacrosEnvironment.instance.publicMacrosFolder.copyTo(compileRoot);

      compileRoot
          .newFile('.dart_tool/package_config.json')
          .writeAsStringSync(r'''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "test",
      "rootUri": "../test",
      "packageUri": "lib/"
    },
    {
      "name": "_macros",
      "rootUri": "../_macros",
      "packageUri": "lib/"
    },
    {
      "name": "macros",
      "rootUri": "../macros",
      "packageUri": "lib/"
    }
  ]
}
''');

      var process = await io.Process.start(
        io.Platform.executable,
        ['compile', 'exe', '--enable-experiment=macros', testMain.path],
      );

      var exitCode = await process.exitCode;
      if (exitCode == 255 || exitCode == 64) {
        markTestSkipped('Skip because cannot compile.');
        return;
      }
      expect(exitCode, isZero);

      var executable = testBin.getChildAssumingFile('main.exe');
      expect(executable.exists, isTrue);

      // Convert to io.File
      macroExecutable = io.File(executable.path);
    }

    // Build the summary for `a.dart`, with the macro.
    // We always have summaries for libraries with macro executable.
    Uint8List aBundleBytes;
    {
      var a = newFile('$testPackageLibPath/a.dart', macroCode);

      // Disable compilation to kernel.
      macroSupportFactory = ExecutableMacroSupportFactory(
        configure: (_) {},
      );

      var analysisDriver = driverFor(a);
      aBundleBytes = await analysisDriver.buildPackageBundle(
        uriList: [
          Uri.parse('package:_macros/src/api.dart'),
          Uri.parse('package:macros/macros.dart'),
          Uri.parse('package:test/a.dart'),
        ],
      );

      // We should not read the file anyway, but we make it explicit.
      a.delete();
    }

    await disposeAnalysisContextCollection();
    useEmptyByteStore();

    // Configure summaries.
    {
      sdkSummaryFile = await writeSdkSummary();

      var aBundleFile = getFile('/home/summaries/a.sum');
      aBundleFile.writeAsBytesSync(aBundleBytes);
      librarySummaryFiles = [aBundleFile];
    }

    // Configure the macro executor.
    macroSupportFactory = ExecutableMacroSupportFactory(
      configure: (macroSupport) {
        macroSupport.add(
          executable: macroExecutable,
          libraries: {
            Uri.parse('package:test/a.dart'),
          },
        );
      },
    );

    // Verify that we can use the executable to run the macro.
    {
      var library = await buildLibrary(r'''
import 'a.dart';

@MyMacro()
class A {}
''');
      configuration
        ..withConstructors = false
        ..withMetadata = false
        ..withReferences = true;
      checkElementText(library, r'''
library
  reference: self
  imports
    package:test/a.dart
  definingUnit
    reference: self
    classes
      class A @35
        reference: self::@class::A
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class MyClass {}
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          class MyClass @49
            reference: self::@augmentation::package:test/test.macro.dart::@class::MyClass
''');
    }
  }

  test_imports_class() async {
    useEmptyByteStore();

    newFile('$testPackageLibPath/a.dart', r'''
class A {}
''');

    newFile('$testPackageLibPath/b.dart', r'''
import 'dart:async';
import 'package:macros/macros.dart';
import 'a.dart';

macro class MyMacro implements ClassTypesMacro {
  const MyMacro();

  buildTypesForClass(clazz, ClassTypeBuilder builder) async {
    final identifier = await builder.resolveIdentifier(
      Uri.parse('package:test/a.dart'),
      'A',
    );
    builder.declareType(
      'MyClass',
      DeclarationCode.fromParts([
        'class MyClass {\n  void foo(',
        identifier,
        ' _) {}\n}',
      ]),
    );
  }
}
''');

    var library = await buildLibrary(r'''
import 'b.dart';

@MyMacro()
class X {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/b.dart
  definingUnit
    classes
      class X @35
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

class MyClass {
  void foo(prefix0.A _) {}
}
---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          class MyClass @91
            methods
              foo @108
                parameters
                  requiredPositional _ @122
                    type: A
                returnType: void
''');

    analyzerStatePrinterConfiguration.filesToPrintContent.add(
      getFile('$testPackageLibPath/test.macro.dart'),
    );

    if (keepLinkingLibraries) {
      assertDriverStateString(testFile, r'''
files
  /home/test/lib/a.dart
    uri: package:test/a.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_12 dart:core synthetic
        cycle_0
          dependencies: dart:core
          libraries: library_0
          apiSignature_0
          users: cycle_1
      referencingFiles: file_1 file_3
      unlinkedKey: k00
  /home/test/lib/b.dart
    uri: package:test/b.dart
    current
      id: file_1
      kind: library_1
        libraryImports
          library_14 dart:async
          library_11 package:macros/macros.dart
          library_0
          library_12 dart:core synthetic
        cycle_1
          dependencies: cycle_0 dart:core package:macros/macros.dart
          libraries: library_1
          apiSignature_1
          users: cycle_2
      referencingFiles: file_2
      unlinkedKey: k01
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_2
      kind: library_2
        libraryImports
          library_1
          library_12 dart:core synthetic
        augmentationImports
          augmentation_3
        cycle_2
          dependencies: cycle_1 dart:core
          libraries: library_2
          apiSignature_2
      unlinkedKey: k02
  /home/test/lib/test.macro.dart
    uri: package:test/test.macro.dart
    current
      id: file_3
      content
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

class MyClass {
  void foo(prefix0.A _) {}
}
---
      kind: augmentation_3
        augmented: library_2
        library: library_2
        libraryImports
          library_0
          library_12 dart:core synthetic
      referencingFiles: file_2
      unlinkedKey: k03
libraryCycles
  /home/test/lib/a.dart
    current: cycle_0
      key: k04
    get: []
    put: [k04]
  /home/test/lib/b.dart
    current: cycle_1
      key: k05
    get: []
    put: [k05]
  /home/test/lib/test.dart
    current: cycle_2
      key: k06
    get: []
    put: [k06]
elementFactory
  hasElement
    package:test/a.dart
    package:test/b.dart
    package:test/test.dart
''');

      // When we discard the library, we keep its macro file.
      driverFor(testFile).changeFile(testFile.path);
      await driverFor(testFile).applyPendingFileChanges();
      assertDriverStateString(testFile, r'''
files
  /home/test/lib/a.dart
    uri: package:test/a.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_12 dart:core synthetic
        cycle_0
          dependencies: dart:core
          libraries: library_0
          apiSignature_0
          users: cycle_1
      referencingFiles: file_1 file_3
      unlinkedKey: k00
  /home/test/lib/b.dart
    uri: package:test/b.dart
    current
      id: file_1
      kind: library_1
        libraryImports
          library_14 dart:async
          library_11 package:macros/macros.dart
          library_0
          library_12 dart:core synthetic
        cycle_1
          dependencies: cycle_0 dart:core package:macros/macros.dart
          libraries: library_1
          apiSignature_1
          users: cycle_7
      referencingFiles: file_2
      unlinkedKey: k01
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_2
      kind: library_18
        libraryImports
          library_1
          library_12 dart:core synthetic
        cycle_7
          dependencies: cycle_1 dart:core
          libraries: library_18
          apiSignature_2
      unlinkedKey: k02
  /home/test/lib/test.macro.dart
    uri: package:test/test.macro.dart
    current
      id: file_3
      content
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

class MyClass {
  void foo(prefix0.A _) {}
}
---
      kind: augmentation_3
        uriFile: file_2
        libraryImports
          library_0
          library_12 dart:core synthetic
      referencingFiles: file_2
      unlinkedKey: k03
libraryCycles
  /home/test/lib/a.dart
    current: cycle_0
      key: k04
    get: []
    put: [k04]
  /home/test/lib/b.dart
    current: cycle_1
      key: k05
    get: []
    put: [k05]
  /home/test/lib/test.dart
    get: []
    put: [k06]
elementFactory
  hasElement
    package:test/a.dart
    package:test/b.dart
''');
    } else {
      assertDriverStateString(testFile, r'''
files
  /home/test/lib/a.dart
    uri: package:test/a.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_12 dart:core synthetic
        cycle_0
          dependencies: dart:core
          libraries: library_0
          apiSignature_0
          users: cycle_1
      referencingFiles: file_1 file_3
      unlinkedKey: k00
  /home/test/lib/b.dart
    uri: package:test/b.dart
    current
      id: file_1
      kind: library_1
        libraryImports
          library_14 dart:async
          library_11 package:macros/macros.dart
          library_0
          library_12 dart:core synthetic
        cycle_1
          dependencies: cycle_0 dart:core package:macros/macros.dart
          libraries: library_1
          apiSignature_1
          users: cycle_2
      referencingFiles: file_2
      unlinkedKey: k01
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_2
      kind: library_2
        libraryImports
          library_1
          library_12 dart:core synthetic
        augmentationImports
          augmentation_3
        cycle_2
          dependencies: cycle_1 dart:core
          libraries: library_2
          apiSignature_2
      unlinkedKey: k02
  /home/test/lib/test.macro.dart
    uri: package:test/test.macro.dart
    current
      id: file_3
      content
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

class MyClass {
  void foo(prefix0.A _) {}
}
---
      kind: augmentation_3
        augmented: library_2
        library: library_2
        libraryImports
          library_0
          library_12 dart:core synthetic
      referencingFiles: file_2
      unlinkedKey: k03
libraryCycles
  /home/test/lib/a.dart
    current: cycle_0
      key: k04
    get: []
    put: [k04]
  /home/test/lib/b.dart
    current: cycle_1
      key: k05
    get: []
    put: [k05]
  /home/test/lib/test.dart
    current: cycle_2
      key: k06
    get: [k06]
    put: [k06]
elementFactory
  hasElement
    package:test/a.dart
    package:test/b.dart
    package:test/test.dart
  hasReader
    package:test/test.dart
''');
    }
  }

  test_iterate_merge() async {
    useEmptyByteStore();

    newFile('$testPackageLibPath/a.dart', r'''
import 'package:macros/macros.dart';

macro class AddClassA implements ClassTypesMacro {
  const AddClassA();

  buildTypesForClass(clazz, builder) async {
    final identifier = await builder.resolveIdentifier(
      Uri.parse('package:test/a.dart'),
      'AddClassB',
    );
    builder.declareType(
      'MyClass',
      DeclarationCode.fromParts([
        '@',
        identifier,
        '()\nclass A {}\n',
      ]),
    );
  }
}

macro class AddClassB implements ClassTypesMacro {
  const AddClassB();

  buildTypesForClass(clazz, builder) async {
    builder.declareType(
      'B',
      DeclarationCode.fromString('class B {}\n'),
    );
  }
}
''');

    var library = await buildLibrary(r'''
import 'a.dart';

@AddClassA()
class X {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/a.dart
  definingUnit
    classes
      class X @37
  augmentationImports
    package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.AddClassB()
class A {}

class B {}

---
      imports
        package:test/a.dart as prefix0 @75
      definingUnit
        classes
          class A @112
          class B @124
''');

    analyzerStatePrinterConfiguration.filesToPrintContent.add(
      getFile('$testPackageLibPath/test.macro.dart'),
    );

    if (keepLinkingLibraries) {
      assertDriverStateString(testFile, r'''
files
  /home/test/lib/a.dart
    uri: package:test/a.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_10 package:macros/macros.dart
          library_11 dart:core synthetic
        cycle_0
          dependencies: dart:core package:macros/macros.dart
          libraries: library_0
          apiSignature_0
          users: cycle_1
      referencingFiles: file_1 file_2
      unlinkedKey: k00
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_1
      kind: library_1
        libraryImports
          library_0
          library_11 dart:core synthetic
        augmentationImports
          augmentation_2
        cycle_1
          dependencies: cycle_0 dart:core
          libraries: library_1
          apiSignature_1
      unlinkedKey: k01
  /home/test/lib/test.macro.dart
    uri: package:test/test.macro.dart
    current
      id: file_2
      content
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.AddClassB()
class A {}

class B {}

---
      kind: augmentation_2
        augmented: library_1
        library: library_1
        libraryImports
          library_0
          library_11 dart:core synthetic
      referencingFiles: file_1
      unlinkedKey: k02
libraryCycles
  /home/test/lib/a.dart
    current: cycle_0
      key: k03
    get: []
    put: [k03]
  /home/test/lib/test.dart
    current: cycle_1
      key: k04
    get: []
    put: [k04]
elementFactory
  hasElement
    package:test/a.dart
    package:test/test.dart
''');
    } else {
      assertDriverStateString(testFile, r'''
files
  /home/test/lib/a.dart
    uri: package:test/a.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_10 package:macros/macros.dart
          library_11 dart:core synthetic
        cycle_0
          dependencies: dart:core package:macros/macros.dart
          libraries: library_0
          apiSignature_0
          users: cycle_1
      referencingFiles: file_1 file_2
      unlinkedKey: k00
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_1
      kind: library_1
        libraryImports
          library_0
          library_11 dart:core synthetic
        augmentationImports
          augmentation_2
        cycle_1
          dependencies: cycle_0 dart:core
          libraries: library_1
          apiSignature_1
      unlinkedKey: k01
  /home/test/lib/test.macro.dart
    uri: package:test/test.macro.dart
    current
      id: file_2
      content
---
augment library 'package:test/test.dart';

import 'package:test/a.dart' as prefix0;

@prefix0.AddClassB()
class A {}

class B {}

---
      kind: augmentation_2
        augmented: library_1
        library: library_1
        libraryImports
          library_0
          library_11 dart:core synthetic
      referencingFiles: file_1
      unlinkedKey: k02
libraryCycles
  /home/test/lib/a.dart
    current: cycle_0
      key: k03
    get: []
    put: [k03]
  /home/test/lib/test.dart
    current: cycle_1
      key: k04
    get: [k04]
    put: [k04]
elementFactory
  hasElement
    package:test/a.dart
    package:test/test.dart
  hasReader
    package:test/test.dart
''');
    }
  }

  test_libraryCycle_class_add() async {
    // Checks https://github.com/dart-lang/sdk/issues/55360
    newFile('$testPackageLibPath/a.dart', r'''
import 'append.dart';

// Just to make it a library cycle.
import 'test.dart';

@DeclareType('X', 'class X {}')
class A {}
''');

    var library = await buildLibrary(r'''
import 'append.dart';
import 'a.dart';

@DeclareType('X', 'class X {}')
class B {}
''');

    configuration
      ..withConstructors = false
      ..withMetadata = false
      ..withReferences = true;
    checkElementText(library, r'''
library
  reference: self
  imports
    package:test/append.dart
    package:test/a.dart
  definingUnit
    reference: self
    classes
      class B @78
        reference: self::@class::B
  augmentationImports
    package:test/test.macro.dart
      reference: self::@augmentation::package:test/test.macro.dart
      macroGeneratedCode
---
augment library 'package:test/test.dart';

class X {}
---
      definingUnit
        reference: self::@augmentation::package:test/test.macro.dart
        classes
          class X @49
            reference: self::@augmentation::package:test/test.macro.dart::@class::X
''');
  }

  test_macroGeneratedFile_changeLibrary_noMacroApplication_restore() async {
    if (!keepLinkingLibraries) return;
    useEmptyByteStore();

    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareTypesPhase('B', 'class B {}')
class A {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

class B {}
''');

    // Note that we have `test.macro.dart` file.
    assertDriverStateString(testFile, r'''
files
  /home/test/lib/append.dart
    uri: package:test/append.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_10 package:macros/macros.dart
          library_11 dart:core synthetic
        cycle_0
          dependencies: dart:core package:macros/macros.dart
          libraries: library_0
          apiSignature_0
          users: cycle_1
      referencingFiles: file_1
      unlinkedKey: k00
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_1
      kind: library_1
        libraryImports
          library_0
          library_11 dart:core synthetic
        augmentationImports
          augmentation_2
        cycle_1
          dependencies: cycle_0 dart:core
          libraries: library_1
          apiSignature_1
      unlinkedKey: k01
  /home/test/lib/test.macro.dart
    uri: package:test/test.macro.dart
    current
      id: file_2
      kind: augmentation_2
        augmented: library_1
        library: library_1
        libraryImports
          library_11 dart:core synthetic
      referencingFiles: file_1
      unlinkedKey: k02
libraryCycles
  /home/test/lib/append.dart
    current: cycle_0
      key: k03
    get: []
    put: [k03]
  /home/test/lib/test.dart
    current: cycle_1
      key: k04
    get: []
    put: [k04]
elementFactory
  hasElement
    package:test/append.dart
    package:test/test.dart
''');

    // Change the library content, no macro applications.
    modifyFile2(testFile, r'''
class A {}
''');
    driverFor(testFile).changeFile2(testFile);

    // Ask the library, will be relinked.
    await driverFor(testFile).getLibraryByUri('package:test/test.dart');

    // For `test.dart`.
    // This is the same `FileState` instance.
    // We refreshed it, it has different `unlinkedKey`, `kind`, `cycle`.
    // We linked new summary, and put it into the byte store.
    //
    // For `test.macro.dart`.
    // This is the same `FileState` instance.
    // We did not refresh it, same `unlinkedKey`, `kind`.
    // Its `kind.library` is empty, `test.dart` does not import it.
    assertDriverStateString(testFile, r'''
files
  /home/test/lib/append.dart
    uri: package:test/append.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_10 package:macros/macros.dart
          library_11 dart:core synthetic
        cycle_0
          dependencies: dart:core package:macros/macros.dart
          libraries: library_0
          apiSignature_0
      unlinkedKey: k00
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_1
      kind: library_17
        libraryImports
          library_11 dart:core synthetic
        cycle_6
          dependencies: dart:core
          libraries: library_17
          apiSignature_2
      unlinkedKey: k05
  /home/test/lib/test.macro.dart
    uri: package:test/test.macro.dart
    current
      id: file_2
      kind: augmentation_2
        uriFile: file_1
        libraryImports
          library_11 dart:core synthetic
      referencingFiles: file_1
      unlinkedKey: k02
libraryCycles
  /home/test/lib/append.dart
    current: cycle_0
      key: k03
    get: []
    put: [k03]
  /home/test/lib/test.dart
    current: cycle_6
      key: k06
    get: []
    put: [k04, k06]
elementFactory
  hasElement
    package:test/append.dart
    package:test/test.dart
''');

    // Use the same library as initially.
    modifyFile2(testFile, r'''
import 'append.dart';

@DeclareTypesPhase('B', 'class B {}')
class A {}
''');
    driverFor(testFile).changeFile2(testFile);

    // Ask the library, will be relinked.
    await driverFor(testFile).getLibraryByUri('package:test/test.dart');

    // For `test.dart`.
    // This is the same `FileState` instance.
    // We refreshed it, it has different `unlinkedKey`, `kind`, `cycle`.
    // We read the linked summary, see `get`.
    //
    // For `test.macro.dart`.
    // This is the same `FileState` instance.
    // Its content is the same as it already was, so we did not `refresh()` it.
    // Its `kind.library` now points at the new `kind` of `test.dart`.
    assertDriverStateString(testFile, r'''
files
  /home/test/lib/append.dart
    uri: package:test/append.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_10 package:macros/macros.dart
          library_11 dart:core synthetic
        cycle_0
          dependencies: dart:core package:macros/macros.dart
          libraries: library_0
          apiSignature_0
          users: cycle_7
      referencingFiles: file_1
      unlinkedKey: k00
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_1
      kind: library_18
        libraryImports
          library_0
          library_11 dart:core synthetic
        augmentationImports
          augmentation_2
        cycle_7
          dependencies: cycle_0 dart:core
          libraries: library_18
          apiSignature_1
      unlinkedKey: k01
  /home/test/lib/test.macro.dart
    uri: package:test/test.macro.dart
    current
      id: file_2
      kind: augmentation_2
        augmented: library_18
        library: library_18
        libraryImports
          library_11 dart:core synthetic
      referencingFiles: file_1
      unlinkedKey: k02
libraryCycles
  /home/test/lib/append.dart
    current: cycle_0
      key: k03
    get: []
    put: [k03]
  /home/test/lib/test.dart
    current: cycle_7
      key: k04
    get: [k04]
    put: [k04, k06]
elementFactory
  hasElement
    package:test/append.dart
    package:test/test.dart
  hasReader
    package:test/test.dart
''');
  }

  test_macroGeneratedFile_changeLibrary_updateMacroApplication() async {
    if (!keepLinkingLibraries) return;
    useEmptyByteStore();

    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareTypesPhase('B', 'class B {}')
class A {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

class B {}
''');

    // Note that we have `test.macro.dart` file.
    assertDriverStateString(testFile, r'''
files
  /home/test/lib/append.dart
    uri: package:test/append.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_10 package:macros/macros.dart
          library_11 dart:core synthetic
        cycle_0
          dependencies: dart:core package:macros/macros.dart
          libraries: library_0
          apiSignature_0
          users: cycle_1
      referencingFiles: file_1
      unlinkedKey: k00
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_1
      kind: library_1
        libraryImports
          library_0
          library_11 dart:core synthetic
        augmentationImports
          augmentation_2
        cycle_1
          dependencies: cycle_0 dart:core
          libraries: library_1
          apiSignature_1
      unlinkedKey: k01
  /home/test/lib/test.macro.dart
    uri: package:test/test.macro.dart
    current
      id: file_2
      kind: augmentation_2
        augmented: library_1
        library: library_1
        libraryImports
          library_11 dart:core synthetic
      referencingFiles: file_1
      unlinkedKey: k02
libraryCycles
  /home/test/lib/append.dart
    current: cycle_0
      key: k03
    get: []
    put: [k03]
  /home/test/lib/test.dart
    current: cycle_1
      key: k04
    get: []
    put: [k04]
elementFactory
  hasElement
    package:test/append.dart
    package:test/test.dart
''');

    // Change the library content.
    modifyFile2(testFile, r'''
import 'append.dart';

@DeclareTypesPhase('B2', 'class B2 {}')
class A {}
''');
    driverFor(testFile).changeFile2(testFile);

    // Ask the library, will be relinked.
    var result2 =
        await driverFor(testFile).getLibraryByUri('package:test/test.dart');

    // For `test.dart`.
    // This is the same `FileState` instance.
    // We refreshed it, it has different `unlinkedKey`, `kind`, `cycle`.
    // We linked new summary, and put it into the byte store.
    //
    // For `test.macro.dart`.
    // This is the same `FileState` instance.
    // We refreshed it, it has different `unlinkedKey`, `kind`.
    // Its `library` points at `test.dart` library.
    assertDriverStateString(testFile, r'''
files
  /home/test/lib/append.dart
    uri: package:test/append.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_10 package:macros/macros.dart
          library_11 dart:core synthetic
        cycle_0
          dependencies: dart:core package:macros/macros.dart
          libraries: library_0
          apiSignature_0
          users: cycle_6
      referencingFiles: file_1
      unlinkedKey: k00
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_1
      kind: library_17
        libraryImports
          library_0
          library_11 dart:core synthetic
        augmentationImports
          augmentation_18
        cycle_6
          dependencies: cycle_0 dart:core
          libraries: library_17
          apiSignature_2
      unlinkedKey: k05
  /home/test/lib/test.macro.dart
    uri: package:test/test.macro.dart
    current
      id: file_2
      kind: augmentation_18
        augmented: library_17
        library: library_17
        libraryImports
          library_11 dart:core synthetic
      referencingFiles: file_1
      unlinkedKey: k06
libraryCycles
  /home/test/lib/append.dart
    current: cycle_0
      key: k03
    get: []
    put: [k03]
  /home/test/lib/test.dart
    current: cycle_6
      key: k07
    get: []
    put: [k04, k07]
elementFactory
  hasElement
    package:test/append.dart
    package:test/test.dart
''');

    // Check that it has `class B2 {}`, as requested.
    result2 as LibraryElementResultImpl;
    _assertMacroCode(result2.element as LibraryElementImpl, r'''
augment library 'package:test/test.dart';

class B2 {}
''');
  }

  test_macroGeneratedFile_dispose_restore() async {
    if (!keepLinkingLibraries) return;
    useEmptyByteStore();

    var library = await buildLibrary(r'''
import 'append.dart';

@DeclareTypesPhase('B', 'class B {}')
class A {}
''');

    _assertMacroCode(library, r'''
augment library 'package:test/test.dart';

class B {}
''');

    // Note that we have `test.macro.dart` file.
    assertDriverStateString(testFile, r'''
files
  /home/test/lib/append.dart
    uri: package:test/append.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_10 package:macros/macros.dart
          library_11 dart:core synthetic
        cycle_0
          dependencies: dart:core package:macros/macros.dart
          libraries: library_0
          apiSignature_0
          users: cycle_1
      referencingFiles: file_1
      unlinkedKey: k00
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_1
      kind: library_1
        libraryImports
          library_0
          library_11 dart:core synthetic
        augmentationImports
          augmentation_2
        cycle_1
          dependencies: cycle_0 dart:core
          libraries: library_1
          apiSignature_1
      unlinkedKey: k01
  /home/test/lib/test.macro.dart
    uri: package:test/test.macro.dart
    current
      id: file_2
      kind: augmentation_2
        augmented: library_1
        library: library_1
        libraryImports
          library_11 dart:core synthetic
      referencingFiles: file_1
      unlinkedKey: k02
libraryCycles
  /home/test/lib/append.dart
    current: cycle_0
      key: k03
    get: []
    put: [k03]
  /home/test/lib/test.dart
    current: cycle_1
      key: k04
    get: []
    put: [k04]
elementFactory
  hasElement
    package:test/append.dart
    package:test/test.dart
''');

    // "Touch" the library file, so dispose it.
    // But don't load the library yet.
    driverFor(testFile).changeFile2(testFile);
    await pumpEventQueue(times: 5000);

    // For `test.dart`.
    // No `current` in `libraryCycles`, it was disposed.
    // It has a new instance `cycle_X`.
    // Actually the cycle was also disposed, but the printer re-created it.
    //
    // For `test.macro.dart`.
    // It still has the same `current`.
    // No `current` library cycle.
    assertDriverStateString(testFile, r'''
files
  /home/test/lib/append.dart
    uri: package:test/append.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_10 package:macros/macros.dart
          library_11 dart:core synthetic
        cycle_0
          dependencies: dart:core package:macros/macros.dart
          libraries: library_0
          apiSignature_0
          users: cycle_6
      referencingFiles: file_1
      unlinkedKey: k00
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_1
      kind: library_17
        libraryImports
          library_0
          library_11 dart:core synthetic
        cycle_6
          dependencies: cycle_0 dart:core
          libraries: library_17
          apiSignature_1
      unlinkedKey: k01
  /home/test/lib/test.macro.dart
    uri: package:test/test.macro.dart
    current
      id: file_2
      kind: augmentation_2
        uriFile: file_1
        libraryImports
          library_11 dart:core synthetic
      referencingFiles: file_1
      unlinkedKey: k02
libraryCycles
  /home/test/lib/append.dart
    current: cycle_0
      key: k03
    get: []
    put: [k03]
  /home/test/lib/test.dart
    get: []
    put: [k04]
elementFactory
  hasElement
    package:test/append.dart
''');

    // Load the library from bytes.
    await driverFor(testFile).getLibraryByUri('package:test/test.dart');

    // For `test.dart`.
    // It has `current` in `libraryCycles`.
    // This is a new instance.
    // It has `get` with the same id as was put before.
    //
    // For `test.macro.dart`.
    // The same instance of `kind` as before.
    // We read the `test.dart` linked summary from bytes, and added the
    // augmentation file `test.macro.dart` from the stored the code. The code
    // was the same as before, so we did not `refresh()` the file. So, we did
    // not change the existing `kind`.
    assertDriverStateString(testFile, r'''
files
  /home/test/lib/append.dart
    uri: package:test/append.dart
    current
      id: file_0
      kind: library_0
        libraryImports
          library_10 package:macros/macros.dart
          library_11 dart:core synthetic
        cycle_0
          dependencies: dart:core package:macros/macros.dart
          libraries: library_0
          apiSignature_0
          users: cycle_6
      referencingFiles: file_1
      unlinkedKey: k00
  /home/test/lib/test.dart
    uri: package:test/test.dart
    current
      id: file_1
      kind: library_17
        libraryImports
          library_0
          library_11 dart:core synthetic
        augmentationImports
          augmentation_2
        cycle_6
          dependencies: cycle_0 dart:core
          libraries: library_17
          apiSignature_1
      unlinkedKey: k01
  /home/test/lib/test.macro.dart
    uri: package:test/test.macro.dart
    current
      id: file_2
      kind: augmentation_2
        augmented: library_17
        library: library_17
        libraryImports
          library_11 dart:core synthetic
      referencingFiles: file_1
      unlinkedKey: k02
libraryCycles
  /home/test/lib/append.dart
    current: cycle_0
      key: k03
    get: []
    put: [k03]
  /home/test/lib/test.dart
    current: cycle_6
      key: k04
    get: [k04]
    put: [k04]
elementFactory
  hasElement
    package:test/append.dart
    package:test/test.dart
  hasReader
    package:test/test.dart
''');
  }

  test_multipleAnalysisContexts() async {
    // No need to verify reading elements for this test.
    if (!keepLinkingLibraries) {
      return;
    }

    var otherRootPath = '$workspaceRootPath/other';
    var otherPackageConfig = PackageConfigFileBuilder()
      ..add(name: 'test', rootPath: testPackageRootPath)
      ..add(name: 'other', rootPath: otherRootPath);
    addMacrosEnvironment(
      otherPackageConfig,
      MacrosEnvironment.instance,
    );
    writePackageConfig(
      otherRootPath,
      otherPackageConfig,
    );

    newAnalysisOptionsYamlFile(
      otherRootPath,
      AnalysisOptionsFileConfig(
        experiments: experiments,
      ).toContent(),
    );

    var file = newFile('$otherRootPath/lib/other.dart', r'''
import 'package:test/append.dart';

@DeclareType('B', 'class B {}')
class A {}
''');

    // Load the macro itself, in `package:test` analysis context.
    await libraryElementForFile(
      getFile('$testPackageLibPath/append.dart'),
    );

    // Load the macro from dependency, in `package:other` analysis context.
    // It should not crash.
    var library = await libraryElementForFile(file);

    // ...but check it a little more.
    configuration
      ..withConstructors = false
      ..withMetadata = false;
    checkElementText(library, r'''
library
  imports
    package:test/append.dart
  definingUnit
    classes
      class A @74
  augmentationImports
    package:other/other.macro.dart
      macroGeneratedCode
---
augment library 'package:other/other.dart';

class B {}
---
      definingUnit
        classes
          class B @51
''');
  }
}

@reflectiveTest
class MacroTypesTest_fromBytes extends MacroTypesTest {
  @override
  bool get keepLinkingLibraries => false;
}

@reflectiveTest
class MacroTypesTest_keepLinking extends MacroTypesTest {
  @override
  bool get keepLinkingLibraries => true;
}

class _MacroDiagnosticsCollector extends GeneralizingElementVisitor<void> {
  final List<AnalyzerMacroDiagnostic> diagnostics = [];

  @override
  void visitElement(Element element) {
    if (element case MacroTargetElement element) {
      diagnostics.addAll(element.macroDiagnostics);
    }

    super.visitElement(element);
  }
}

extension on LibraryElement {
  List<AnalyzerMacroDiagnostic> get allMacroDiagnostics {
    var collector = _MacroDiagnosticsCollector();
    accept(collector);
    return collector.diagnostics;
  }
}

extension on Folder {
  File newFile(String relPath) {
    var file = getChildAssumingFile(relPath);
    file.parent.create();
    return file;
  }
}

extension on ElementTextConfiguration {
  void forCodeOptimizer() {
    filter = (obj) {
      if (obj is CompilationUnitElement) {
        return obj.enclosingElement is LibraryAugmentationElement;
      }
      return true;
    };
    withConstructors = false;
    withMetadata = true;
  }

  void forOrder() {
    filter = (element) {
      if (element is CompilationUnitElement) {
        return false;
        // return element.source.uri != Uri.parse('package:test/test.dart');
      }
      return true;
    };
    withConstructors = false;
    withMetadata = false;
    withReturnType = false;
  }
}
