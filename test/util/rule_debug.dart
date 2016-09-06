// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:path/path.dart' as p;

import '../rule_test.dart';

/// Solo rule test runner.  Handy for debugging.
///
/// Run, for example, like so:
///     dart test/util/rule_debug.dart valid_regexps
///
/// To simply run a solo test, consider using `pub run test -N`:
///     pub run test -N valid_regexps
///
main(List<String> args) {
  String ruleName = args[0];
  Directory dir = new Directory(ruleDir).absolute;
  testRule(ruleName, new File(p.join(dir.path, '$ruleName.dart')), debug: true);
}
