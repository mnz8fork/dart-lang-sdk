// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library linter.src.rules.do_not_catch_errors;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:linter/src/analyzer.dart';
import 'package:linter/src/util/dart_type_utilities.dart';

const _desc = r'Don’t explicitly catch Error or types that implement it.';

const _details = r'''

**DON’T** explicitly catch Error or types that implement it.

**BAD:**
```
try {
  somethingRisky();
} on Error catch(e) {
  doSomething(e);
}
```

**GOOD:**
```
try {
  somethingRisky();
} on Exception catch(e) {
  doSomething(e);
}
```

''';

class DoNotCatchErrors extends LintRule {
  _Visitor _visitor;
  DoNotCatchErrors()
      : super(
            name: 'do_not_catch_errors',
            description: _desc,
            details: _details,
            group: Group.style) {
    _visitor = new _Visitor(this);
  }

  @override
  AstVisitor getVisitor() => _visitor;
}

class _Visitor extends SimpleAstVisitor {
  final LintRule rule;
  _Visitor(this.rule);

  @override
  visitCatchClause(CatchClause node) {
    final exceptionType = node.exceptionType?.type;
    if (DartTypeUtilities.implementsInterface(
        exceptionType, 'Error', 'dart.core')) {
      rule.reportLint(node);
    }
  }
}
