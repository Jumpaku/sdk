// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart';
import 'package:kernel/target/targets.dart';

import '../../codes/cfe_codes.dart';
import 'constant_evaluator.dart';

abstract class ConstantIntFolder {
  final ConstantEvaluator evaluator;

  ConstantIntFolder(this.evaluator);

  factory ConstantIntFolder.forSemantics(
      ConstantEvaluator evaluator, NumberSemantics semantics) {
    if (semantics == NumberSemantics.js) {
      return new JsConstantIntFolder(evaluator);
    } else {
      return new VmConstantIntFolder(evaluator);
    }
  }

  /// Returns `true` of [constant] is an integer value.
  bool isInt(Constant constant);

  /// Returns the value of [constant] as an [int], of `null` [constant] is
  /// not an integer value.
  ///
  /// This method must return a non-null value iff `isInt(constant)` returns
  /// `true`.
  int? asInt(Constant constant);

  Constant makeIntConstant(int value, {bool unsigned = false});

  Constant foldUnaryOperator(
      Expression node, String op, covariant Constant operand);

  Constant foldBinaryOperator(Expression node, String op,
      covariant Constant left, covariant Constant right);

  Constant truncatingDivide(Expression node, num left, num right);

  /// Returns [null] on success and an error-"constant" on failure, as such the
  /// return value should be checked.
  AbortConstant? _checkOperands(
      Expression node, String op, num left, num right) {
    if ((op == '<<' || op == '>>' || op == '>>>') && right < 0) {
      return evaluator.createEvaluationErrorConstant(node,
          templateConstEvalNegativeShift.withArguments(op, '$left', '$right'));
    }
    if ((op == '%' || op == '~/') && right == 0) {
      return evaluator.createEvaluationErrorConstant(
          node, templateConstEvalZeroDivisor.withArguments(op, '$left'));
    }
    return null;
  }
}

class VmConstantIntFolder extends ConstantIntFolder {
  VmConstantIntFolder(ConstantEvaluator evaluator) : super(evaluator);

  @override
  bool isInt(Constant constant) => constant is IntConstant;

  @override
  int? asInt(Constant constant) {
    if (constant is IntConstant) {
      return constant.value;
    }
    return null;
  }

  @override
  IntConstant makeIntConstant(int value, {bool unsigned = false}) {
    return new IntConstant(value);
  }

  @override
  Constant foldUnaryOperator(Expression node, String op, IntConstant operand) {
    switch (op) {
      case 'unary-':
        return new IntConstant(-operand.value);
      case '~':
        return new IntConstant(~operand.value);
      default:
        // Probably unreachable.
        return evaluator.createExpressionErrorConstant(
            node,
            templateNotConstantExpression
                .withArguments("Unary '$op' operation"));
    }
  }

  @override
  Constant foldBinaryOperator(
      Expression node, String op, IntConstant left, IntConstant right) {
    int a = left.value;
    int b = right.value;
    AbortConstant? error = _checkOperands(node, op, a, b);
    if (error != null) return error;
    switch (op) {
      case '+':
        return new IntConstant(a + b);
      case '-':
        return new IntConstant(a - b);
      case '*':
        return new IntConstant(a * b);
      case '/':
        return new DoubleConstant(a / b);
      case '~/':
        return new IntConstant(a ~/ b);
      case '%':
        return new IntConstant(a % b);
      case '|':
        return new IntConstant(a | b);
      case '&':
        return new IntConstant(a & b);
      case '^':
        return new IntConstant(a ^ b);
      case '<<':
        return new IntConstant(a << b);
      case '>>':
        return new IntConstant(a >> b);
      case '>>>':
        // Currently unreachable as int hasn't defined '>>>'.
        int result = b >= 64 ? 0 : (a >> b) & ((1 << (64 - b)) - 1);
        return new IntConstant(result);
      case '<':
        return evaluator.makeBoolConstant(a < b);
      case '<=':
        return evaluator.makeBoolConstant(a <= b);
      case '>=':
        return evaluator.makeBoolConstant(a >= b);
      case '>':
        return evaluator.makeBoolConstant(a > b);
      default:
        // Probably unreachable.
        return evaluator.createExpressionErrorConstant(
            node,
            templateNotConstantExpression
                .withArguments("Binary '$op' operation"));
    }
  }

  @override
  Constant truncatingDivide(Expression node, num left, num right) {
    try {
      return new IntConstant(left ~/ right);
    } catch (e) {
      return evaluator.createEvaluationErrorConstant(node,
          templateConstEvalTruncateError.withArguments('$left', '$right'));
    }
  }
}

class JsConstantIntFolder extends ConstantIntFolder {
  JsConstantIntFolder(ConstantEvaluator evaluator) : super(evaluator);

  static bool _valueIsInteger(double value) {
    return value.isFinite && value.truncateToDouble() == value;
  }

  static int _truncate32(int value) => value & 0xFFFFFFFF;

  static int _toUint32(double value) {
    return new BigInt.from(value).toUnsigned(32).toInt();
  }

  @override
  bool isInt(Constant constant) {
    return constant is DoubleConstant && _valueIsInteger(constant.value);
  }

  @override
  int? asInt(Constant constant) {
    if (constant is DoubleConstant && _valueIsInteger(constant.value)) {
      return constant.value.toInt();
    }
    return null;
  }

  @override
  DoubleConstant makeIntConstant(int value, {bool unsigned = false}) {
    double doubleValue = value.toDouble();
    // Invalid assert: assert(doubleValue.toInt() == value);
    if (unsigned) {
      const double twoTo64 = 18446744073709551616.0;
      if (value < 0) doubleValue += twoTo64;
    }
    return new DoubleConstant(doubleValue);
  }

  @override
  Constant foldUnaryOperator(
      Expression node, String op, DoubleConstant operand) {
    switch (op) {
      case 'unary-':
        return new DoubleConstant(-operand.value);
      case '~':
        int intValue = _toUint32(operand.value);
        return new DoubleConstant(_truncate32(~intValue).toDouble());
      default:
        // Probably unreachable.
        return evaluator.createExpressionErrorConstant(
            node,
            templateNotConstantExpression
                .withArguments("Unary '$op' operation"));
    }
  }

  @override
  Constant foldBinaryOperator(
      Expression node, String op, DoubleConstant left, DoubleConstant right) {
    double a = left.value;
    double b = right.value;
    AbortConstant? error = _checkOperands(node, op, a, b);
    if (error != null) return error;
    switch (op) {
      case '+':
        return new DoubleConstant(a + b);
      case '-':
        return new DoubleConstant(a - b);
      case '*':
        return new DoubleConstant(a * b);
      case '/':
        return new DoubleConstant(a / b);
      case '~/':
        return truncatingDivide(node, a, b);
      case '%':
        return new DoubleConstant(a % b);
      case '|':
        return new DoubleConstant((_toUint32(a) | _toUint32(b)).toDouble());
      case '&':
        return new DoubleConstant((_toUint32(a) & _toUint32(b)).toDouble());
      case '^':
        return new DoubleConstant((_toUint32(a) ^ _toUint32(b)).toDouble());
      case '<<':
        int ai = _toUint32(a);
        return new DoubleConstant(_truncate32(ai << b.toInt()).toDouble());
      case '>>':
        int ai = _toUint32(a);
        if (a < 0) {
          const int signBit = 0x80000000;
          ai -= (ai & signBit) << 1;
        }
        return new DoubleConstant(_truncate32(ai >> b.toInt()).toDouble());
      case '>>>':
        // Currently unreachable as int hasn't defined '>>>'.
        int ai = _toUint32(a);
        return new DoubleConstant(_truncate32(ai >> b.toInt()).toDouble());
      case '<':
        return evaluator.makeBoolConstant(a < b);
      case '<=':
        return evaluator.makeBoolConstant(a <= b);
      case '>=':
        return evaluator.makeBoolConstant(a >= b);
      case '>':
        return evaluator.makeBoolConstant(a > b);
      default:
        // Probably unreachable.
        return evaluator.createExpressionErrorConstant(
            node,
            templateNotConstantExpression
                .withArguments("Binary '$op' operation"));
    }
  }

  @override
  Constant truncatingDivide(Expression node, num left, num right) {
    double division = (left / right);
    if (division.isNaN || division.isInfinite) {
      return evaluator.createEvaluationErrorConstant(node,
          templateConstEvalTruncateError.withArguments('$left', '${right}'));
    }
    double result = division.truncateToDouble();
    return new DoubleConstant(result == 0.0 ? 0.0 : result);
  }
}
