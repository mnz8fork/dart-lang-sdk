// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.scope;

import 'package:kernel/ast.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/type_environment.dart';

import '../builder/builder.dart';
import '../builder/declaration_builders.dart';
import '../builder/member_builder.dart';
import '../builder/metadata_builder.dart';
import '../builder/name_iterator.dart';
import '../builder/prefix_builder.dart';
import '../kernel/body_builder.dart' show JumpTarget;
import '../kernel/body_builder_context.dart';
import '../kernel/hierarchy/class_member.dart' show ClassMember;
import '../kernel/kernel_helper.dart';
import '../kernel/load_library_builder.dart';
import '../source/source_class_builder.dart';
import '../source/source_extension_builder.dart';
import '../source/source_extension_type_declaration_builder.dart';
import '../source/source_function_builder.dart';
import '../source/source_library_builder.dart';
import '../source/source_member_builder.dart';
import '../util/helpers.dart' show DelayedActionPerformer;
import 'messages.dart';
import 'name_space.dart';
import 'uri_offset.dart';

enum ScopeKind {
  /// Scope of pattern switch-case statements
  ///
  /// These scopes receive special treatment in that they are end-points of the
  /// scope stack in presence of multiple heads for the same case, but can have
  /// nested scopes if it's just a single head. In that latter possibility the
  /// body of the case is nested into the scope of the case head. And for switch
  /// expressions that scope includes both the head and the case expression.
  caseHead,

  /// The declaration-level scope for classes, enums, and similar declarations
  declaration,

  /// Scope where the formal parameters of a function are declared
  formals,

  /// Scope of a `for` statement
  forStatement,

  /// Scope of a function body
  functionBody,

  /// Scope of the head of the if-case statement
  ifCaseHead,

  /// Scope of an if-element in a collection
  ifElement,

  /// Scope for the initializers of generative constructors
  initializers,

  /// Scope where the joint variables of a switch case are declared
  jointVariables,

  /// Scope where labels of labelled statements are declared
  labels,

  /// Top-level scope of a library
  library,

  /// The special scope of the named function expression
  ///
  /// This scope is treated separately because the named function expressions
  /// are allowed to be recursive, and the name of that function expression
  /// should be visible in the scope of the function itself.
  namedFunctionExpression,

  /// The scope of the RHS of a binary-or pattern
  ///
  /// It is utilized for separating the branch-local variables from the joint
  /// variables of the overall binary-or pattern.
  orPatternRight,

  /// The scope of a pattern
  ///
  /// It contains the variables associated with pattern variable declarations.
  pattern,

  /// Local scope of a statement, such as the body of a while loop
  statementLocalScope,

  /// Local scope of a switch block
  switchBlock,

  /// Scope for switch cases
  ///
  /// This scope kind is used in assertion checks.
  switchCase,

  /// Scope for switch case bodies
  ///
  /// This is used to handle local variables of switch cases.
  switchCaseBody,

  /// Scope for type parameters of declarations
  typeParameters,
}

abstract class LookupScope {
  ScopeKind get kind;
  Builder? lookup(String name, int charOffset, Uri fileUri);
  Builder? lookupSetter(String name, int charOffset, Uri fileUri);
}

/// Returns the correct value of [builder] found as a lookup of [name].
///
/// This ensures that an [AmbiguousBuilder] is return of the found builder is
/// a duplicate.
Builder? normalizeLookup(Builder? builder,
    {required String name,
    required int charOffset,
    required Uri fileUri,
    required String classNameOrDebugName}) {
  if (builder == null) return null;
  if (builder.next != null) {
    return new AmbiguousBuilder(
        name.isEmpty
            ?
            // Coverage-ignore(suite): Not run.
            classNameOrDebugName
            : name,
        builder,
        charOffset,
        fileUri);
  } else if (builder is MemberBuilder && builder.isConflictingSetter) {
    // TODO(johnniwinther): Use a variant of [AmbiguousBuilder] for this case.
    return null;
  } else {
    return builder;
  }
}

/// Returns the correct value of [builder] found as a lookup of [name] where
/// [builder] is found as a setable in search of a getable or as a getable in
/// search of a setable.
///
/// This ensures that an [AccessErrorBuilder] is returned if a non-problem
/// builder was found.
Builder? normalizeCrossLookup(Builder? builder,
    {required String name, required int charOffset, required Uri fileUri}) {
  if (builder != null && !builder.hasProblem) {
    return new AccessErrorBuilder(name, builder, charOffset, fileUri);
  }
  return builder;
}

mixin LookupScopeMixin implements LookupScope {
  String get classNameOrDebugName;

  Builder? lookupIn(
      String name, int charOffset, Uri fileUri, Map<String, Builder> getables) {
    return normalizeLookup(getables[name],
        name: name,
        charOffset: charOffset,
        fileUri: fileUri,
        classNameOrDebugName: classNameOrDebugName);
  }

  Builder? lookupSetterIn(String name, int charOffset, Uri fileUri,
      Map<String, Builder>? getables) {
    Builder? builder;
    if (getables != null) {
      builder = lookupIn(name, charOffset, fileUri, getables);
      builder = normalizeCrossLookup(builder,
          name: name, charOffset: charOffset, fileUri: fileUri);
    }
    return builder;
  }
}

/// A [LookupScope] based directly on a [NameSpace].
class NameSpaceLookupScope implements LookupScope {
  final NameSpace _nameSpace;

  @override
  final ScopeKind kind;

  final String classNameOrDebugName;

  NameSpaceLookupScope(this._nameSpace, this.kind, this.classNameOrDebugName);

  @override
  Builder? lookup(String name, int charOffset, Uri fileUri) {
    Builder? builder = normalizeLookup(
        _nameSpace.lookupLocalMember(name, setter: false),
        name: name,
        charOffset: charOffset,
        fileUri: fileUri,
        classNameOrDebugName: classNameOrDebugName);
    if (builder != null) {
      return builder;
    }
    return normalizeCrossLookup(
        normalizeLookup(_nameSpace.lookupLocalMember(name, setter: true),
            name: name,
            charOffset: charOffset,
            fileUri: fileUri,
            classNameOrDebugName: classNameOrDebugName),
        name: name,
        charOffset: charOffset,
        fileUri: fileUri);
  }

  @override
  Builder? lookupSetter(String name, int charOffset, Uri fileUri) {
    Builder? builder = normalizeLookup(
        _nameSpace.lookupLocalMember(name, setter: true),
        name: name,
        charOffset: charOffset,
        fileUri: fileUri,
        classNameOrDebugName: classNameOrDebugName);
    if (builder != null) {
      return builder;
    }
    return normalizeCrossLookup(
        normalizeLookup(_nameSpace.lookupLocalMember(name, setter: false),
            name: name,
            charOffset: charOffset,
            fileUri: fileUri,
            classNameOrDebugName: classNameOrDebugName),
        name: name,
        charOffset: charOffset,
        fileUri: fileUri);
  }
}

class TypeParameterScope with LookupScopeMixin {
  final LookupScope _parent;
  final Map<String, Builder> _typeParameters;

  TypeParameterScope(this._parent, this._typeParameters);

  @override
  ScopeKind get kind => ScopeKind.typeParameters;

  @override
  Builder? lookup(String name, int charOffset, Uri fileUri) {
    return lookupIn(name, charOffset, fileUri, _typeParameters) ??
        _parent.lookup(name, charOffset, fileUri);
  }

  @override
  Builder? lookupSetter(String name, int charOffset, Uri fileUri) {
    Builder? builder =
        lookupSetterIn(name, charOffset, fileUri, _typeParameters);
    return builder ?? _parent.lookupSetter(name, charOffset, fileUri);
  }

  @override
  String get classNameOrDebugName => "type parameter";
}

abstract class ParentScope {
  ParentScope? get parent;
  void forEachExtension(void Function(ExtensionBuilder) f);
  Builder? lookup(String name, int charOffset, Uri fileUri);
  Builder? lookupSetter(String name, int charOffset, Uri fileUri);
  int writeOn(StringSink sink);
}

class MutableScope {
  /// Names declared in this scope.
  Map<String, Builder>? _local;

  /// Setters declared in this scope.
  Map<String, MemberBuilder>? _setters;

  /// The extensions declared in this scope.
  ///
  /// This includes all available extensions even if the extensions are not
  /// accessible by name because of duplicate imports.
  ///
  /// For instance:
  ///
  ///   lib1.dart:
  ///     extension Extension on String {
  ///       method1() {}
  ///       staticMethod1() {}
  ///     }
  ///   lib2.dart:
  ///     extension Extension on String {
  ///       method2() {}
  ///       staticMethod2() {}
  ///     }
  ///   main.dart:
  ///     import 'lib1.dart';
  ///     import 'lib2.dart';
  ///
  ///     main() {
  ///       'foo'.method1(); // This method is available.
  ///       'foo'.method2(); // This method is available.
  ///       // These methods are not available because Extension is ambiguous:
  ///       Extension.staticMethod1();
  ///       Extension.staticMethod2();
  ///     }
  ///
  Set<ExtensionBuilder>? _extensions;

  /// The scope that this scope is nested within, or `null` if this is the top
  /// level scope.
  ParentScope? _parent;

  final String classNameOrDebugName;

  final ScopeKind kind;

  MutableScope(this.kind, this._local, this._setters, this._extensions,
      this._parent, this.classNameOrDebugName);

  ParentScope? get parent => _parent;

  @override
  String toString() => "Scope(${kind}, $classNameOrDebugName, ${_local?.keys})";
}

class Scope extends MutableScope
    implements ParentScope, LookupScope, NameSpace {
  /// Indicates whether an attempt to declare new names in this scope should
  /// succeed.
  final bool isModifiable;

  Map<String, JumpTarget>? labels;

  Map<String, JumpTarget>? forwardDeclaredLabels;

  Map<String, List<Builder>>? augmentations;

  Map<String, List<Builder>>? setterAugmentations;

  Scope(
      {required ScopeKind kind,
      Map<String, Builder>? local,
      Map<String, MemberBuilder>? setters,
      Set<ExtensionBuilder>? extensions,
      ParentScope? parent,
      this.augmentations,
      this.setterAugmentations,
      required String debugName,
      this.isModifiable = true})
      : super(kind, local, setters, extensions, parent, debugName);

  Scope.top({required ScopeKind kind, bool isModifiable = false})
      : this(
            kind: kind,
            local: <String, Builder>{},
            setters: <String, MemberBuilder>{},
            debugName: "top",
            isModifiable: isModifiable);

  Scope.nested(Scope parent, String debugName,
      {bool isModifiable = true,
      required ScopeKind kind,
      Map<String, Builder>? local})
      : this(
            kind: kind,
            parent: parent,
            debugName: debugName,
            isModifiable: isModifiable,
            local: local);

  /// Returns an iterator of all members and setters mapped in this scope,
  /// including duplicate members mapped to the same name.
  ///
  /// The iterator does _not_ include the members and setters mapped in the
  /// [parent] scope.
  @override
  @deprecated
  Iterator<Builder> get unfilteredIterator {
    return new ScopeIterator(this);
  }

  /// Returns an iterator of all members and setters mapped in this scope,
  /// including duplicate members mapped to the same name.
  ///
  /// The iterator does _not_ include the members and setters mapped in the
  /// [parent] scope.
  ///
  /// Compared to [unfilteredIterator] this iterator also gives access to the
  /// name that the builders are mapped to.
  @override
  @deprecated
  NameIterator get unfilteredNameIterator {
    return new ScopeNameIterator(this);
  }

  /// Returns a filtered iterator of members and setters mapped in this scope.
  ///
  /// Only members of type [T] are included. If [parent] is provided, on members
  /// declared in [parent] are included. If [includeDuplicates] is `true`, all
  /// duplicates of the same name are included, otherwise, only the first
  /// declared member is included. If [includeAugmentations] is `true`, both
  /// original and augmenting/patching members are included, otherwise, only
  /// original members are included.
  @override
  @deprecated
  Iterator<T> filteredIterator<T extends Builder>(
      {Builder? parent,
      required bool includeDuplicates,
      required bool includeAugmentations}) {
    return new FilteredIterator<T>(unfilteredIterator,
        parent: parent,
        includeDuplicates: includeDuplicates,
        includeAugmentations: includeAugmentations);
  }

  /// Returns a filtered iterator of members and setters mapped in this scope.
  ///
  /// Only members of type [T] are included. If [parent] is provided, on members
  /// declared in [parent] are included. If [includeDuplicates] is `true`, all
  /// duplicates of the same name are included, otherwise, only the first
  /// declared member is included. If [includeAugmentations] is `true`, both
  /// original and augmenting/patching members are included, otherwise, only
  /// original members are included.
  ///
  /// Compared to [filteredIterator] this iterator also gives access to the
  /// name that the builders are mapped to.
  @override
  @deprecated
  NameIterator<T> filteredNameIterator<T extends Builder>(
      {Builder? parent,
      required bool includeDuplicates,
      required bool includeAugmentations}) {
    return new FilteredNameIterator<T>(unfilteredNameIterator,
        parent: parent,
        includeDuplicates: includeDuplicates,
        includeAugmentations: includeAugmentations);
  }

  void debug() {
    print("Locals:");
    _local?.forEach((key, value) {
      print("  $key: $value (${identityHashCode(value)}) (${value.parent})");
    });
    print("Setters:");
    _setters?.forEach((key, value) {
      print("  $key: $value (${identityHashCode(value)}) (${value.parent})");
    });
    print("Extensions:");
    _extensions?.forEach((v) {
      print("  $v");
    });
  }

  // Coverage-ignore(suite): Not run.
  Scope copyWithParent(Scope parent, String debugName) {
    return new Scope(
        kind: kind,
        local: super._local,
        setters: super._setters,
        extensions: _extensions,
        parent: parent,
        debugName: debugName,
        isModifiable: isModifiable);
  }

  /// This scope becomes equivalent to [scope]. This is used for parts to
  /// become part of their library's scope.
  void becomePartOf(Scope scope) {
    assert(_parent!.parent == null);
    assert(scope._parent!.parent == null);
    super._local = scope._local;
    super._setters = scope._setters;
    super._parent = scope._parent;
    super._extensions = scope._extensions;
  }

  Scope createNestedScope(
      {required String debugName,
      bool isModifiable = true,
      required ScopeKind kind,
      Map<String, Builder>? local}) {
    return new Scope.nested(this, debugName,
        isModifiable: isModifiable, kind: kind, local: local);
  }

  Scope withTypeVariables(List<NominalVariableBuilder>? typeVariables) {
    if (typeVariables == null) return this;
    Scope newScope = new Scope.nested(this, "type variables",
        isModifiable: false, kind: ScopeKind.typeParameters);
    for (NominalVariableBuilder t in typeVariables) {
      if (t.isWildcard) continue;
      (newScope._local ??= {})[t.name] = t;
    }
    return newScope;
  }

  Scope withStructuralVariables(
      List<StructuralVariableBuilder>? typeVariables) {
    if (typeVariables == null) return this;
    Scope newScope = new Scope.nested(this, "type variables",
        isModifiable: false, kind: ScopeKind.typeParameters);
    for (StructuralVariableBuilder t in typeVariables) {
      (newScope._local ??= {})[t.name] = t;
    }
    return newScope;
  }

  Builder? lookupIn(String name, int charOffset, Uri fileUri,
      Map<String, Builder> map, bool isInstanceScope) {
    Builder? builder = map[name];
    if (builder == null) return null;
    if (builder.next != null) {
      return new AmbiguousBuilder(
          name.isEmpty
              ?
              // Coverage-ignore(suite): Not run.
              classNameOrDebugName
              : name,
          builder,
          charOffset,
          fileUri);
    } else if (!isInstanceScope && builder.isDeclarationInstanceMember) {
      return null;
    } else if (builder is MemberBuilder && builder.isConflictingSetter) {
      // TODO(johnniwinther): Use a variant of [AmbiguousBuilder] for this case.
      return null;
    } else {
      return builder;
    }
  }

  /// Lookup a member with [name] in the scope.
  @override
  Builder? lookup(String name, int charOffset, Uri fileUri,
      {bool isInstanceScope = true}) {
    Builder? builder;
    if (_local != null) {
      builder = lookupIn(name, charOffset, fileUri, _local!, isInstanceScope);
      if (builder != null) return builder;
    }
    if (_setters != null) {
      builder = lookupIn(name, charOffset, fileUri, _setters!, isInstanceScope);
      if (builder != null && !builder.hasProblem) {
        return new AccessErrorBuilder(name, builder, charOffset, fileUri);
      }
      if (!isInstanceScope) {
        // For static lookup, do not search the parent scope.
        return builder;
      }
    }
    return builder ?? _parent?.lookup(name, charOffset, fileUri);
  }

  @override
  Builder? lookupSetter(String name, int charOffset, Uri fileUri,
      {bool isInstanceScope = true}) {
    Builder? builder;
    if (_setters != null) {
      builder = lookupIn(name, charOffset, fileUri, _setters!, isInstanceScope);
      if (builder != null) return builder;
    }
    if (_local != null) {
      builder = lookupIn(name, charOffset, fileUri, _local!, isInstanceScope);
      if (builder != null && !builder.hasProblem) {
        return new AccessErrorBuilder(name, builder, charOffset, fileUri);
      }
      if (!isInstanceScope) {
        // For static lookup, do not search the parent scope.
        return builder;
      }
    }
    return builder ?? _parent?.lookupSetter(name, charOffset, fileUri);
  }

  @override
  @deprecated
  Builder? lookupLocalMember(String name, {required bool setter}) {
    return setter ? (_setters?[name]) : (_local?[name]);
  }

  @override
  @deprecated
  void addLocalMember(String name, Builder member, {required bool setter}) {
    if (setter) {
      (_setters ??= // Coverage-ignore(suite): Not run.
          {})[name] = member as MemberBuilder;
    } else {
      (_local ??= {})[name] = member;
    }
  }

  @override
  @deprecated
  void forEachLocalMember(void Function(String name, Builder member) f) {
    _local?.forEach(f);
  }

  @override
  @deprecated
  void forEachLocalSetter(void Function(String name, MemberBuilder member) f) {
    _setters?.forEach(f);
  }

  @override
  @deprecated
  void forEachLocalExtension(void Function(ExtensionBuilder member) f) {
    _extensions?.forEach(f);
  }

  @override
  @deprecated
  Iterable<Builder> get localMembers => _local?.values ?? const {};

  /// Adds [builder] to the extensions in this scope.
  @override
  @deprecated
  void addExtension(ExtensionBuilder builder) {
    _extensions ??= <ExtensionBuilder>{};
    _extensions!.add(builder);
  }

  /// Calls [f] for each extension in this scope and parent scopes.
  @override
  void forEachExtension(void Function(ExtensionBuilder) f) {
    _extensions?.forEach(f);
    _parent?.forEachExtension(f);
  }

  String get debugString {
    StringBuffer buffer = new StringBuffer();
    int nestingLevel = writeOn(buffer);
    for (int i = nestingLevel; i >= 0; i--) {
      buffer.writeln("${'  ' * i}}");
    }
    return "$buffer";
  }

  // Coverage-ignore(suite): Not run.
  @override
  int writeOn(StringSink sink) {
    int nestingLevel = (_parent?.writeOn(sink) ?? -1) + 1;
    String indent = "  " * nestingLevel;
    sink.writeln("$indent{");
    _local?.forEach((String name, Builder member) {
      sink.writeln("$indent  $name");
    });
    _setters?.forEach((String name, Builder member) {
      sink.writeln("$indent  $name=");
    });
    return nestingLevel;
  }
}

class ConstructorScope {
  /// Constructors declared in this scope.
  final Map<String, MemberBuilder> _local;

  final String className;

  ConstructorScope(this.className, this._local);

  MemberBuilder? lookup(String name, int charOffset, Uri fileUri) {
    MemberBuilder? builder = _local[name];
    if (builder == null) return null;
    if (builder.next != null) {
      return new AmbiguousMemberBuilder(
          name.isEmpty ? className : name, builder, charOffset, fileUri);
    } else {
      return builder;
    }
  }

  MemberBuilder? lookupLocalMember(String name) {
    return _local[name];
  }

  void addLocalMember(String name, MemberBuilder builder) {
    _local[name] = builder;
  }

  void addLocalMembers(Map<String, MemberBuilder> map) {
    _local.addAll(map);
  }

  /// Returns an iterator of all constructors mapped in this scope,
  /// including duplicate constructors mapped to the same name.
  Iterator<MemberBuilder> get unfilteredIterator =>
      new ConstructorScopeIterator(this);

  /// Returns an iterator of all constructors mapped in this scope,
  /// including duplicate constructors mapped to the same name.
  ///
  /// Compared to [unfilteredIterator] this iterator also gives access to the
  /// name that the builders are mapped to.
  NameIterator<MemberBuilder> get unfilteredNameIterator =>
      new ConstructorScopeNameIterator(this);

  /// Returns a filtered iterator of constructors mapped in this scope.
  ///
  /// Only members of type [T] are included. If [parent] is provided, on members
  /// declared in [parent] are included. If [includeDuplicates] is `true`, all
  /// duplicates of the same name are included, otherwise, only the first
  /// declared member is included. If [includeAugmentations] is `true`, both
  /// original and augmenting/patching members are included, otherwise, only
  /// original members are included.
  Iterator<T> filteredIterator<T extends MemberBuilder>(
      {Builder? parent,
      required bool includeDuplicates,
      required bool includeAugmentations}) {
    return new FilteredIterator<T>(unfilteredIterator,
        parent: parent,
        includeDuplicates: includeDuplicates,
        includeAugmentations: includeAugmentations);
  }

  /// Returns a filtered iterator of constructors mapped in this scope.
  ///
  /// Only members of type [T] are included. If [parent] is provided, on members
  /// declared in [parent] are included. If [includeDuplicates] is `true`, all
  /// duplicates of the same name are included, otherwise, only the first
  /// declared member is included. If [includeAugmentations] is `true`, both
  /// original and augmenting/patching members are included, otherwise, only
  /// original members are included.
  ///
  /// Compared to [filteredIterator] this iterator also gives access to the
  /// name that the builders are mapped to.
  NameIterator<T> filteredNameIterator<T extends MemberBuilder>(
      {Builder? parent,
      required bool includeDuplicates,
      required bool includeAugmentations}) {
    return new FilteredNameIterator<T>(unfilteredNameIterator,
        parent: parent,
        includeDuplicates: includeDuplicates,
        includeAugmentations: includeAugmentations);
  }

  @override
  String toString() => "ConstructorScope($className, ${_local.keys})";
}

abstract class LazyScope extends Scope {
  LazyScope(Map<String, Builder> local, Map<String, MemberBuilder> setters,
      Scope? parent, String debugName,
      {bool isModifiable = true, required ScopeKind kind})
      : super(
            kind: kind,
            local: local,
            setters: setters,
            parent: parent,
            debugName: debugName,
            isModifiable: isModifiable);

  /// Override this method to lazily populate the scope before access.
  void ensureScope();

  @override
  Map<String, Builder>? get _local {
    ensureScope();
    return super._local;
  }

  @override
  Map<String, MemberBuilder>? get _setters {
    ensureScope();
    return super._setters;
  }

  @override
  Set<ExtensionBuilder>? get _extensions {
    ensureScope();
    return super._extensions;
  }
}

/// Computes a builder for the import/export collision between [declaration] and
/// [other] and adds it to [nameSpace].
Builder computeAmbiguousDeclarationForScope(ProblemReporting problemReporting,
    NameSpace nameSpace, String name, Builder declaration, Builder other,
    {required UriOffset uriOffset,
    bool isExport = false,
    bool isImport = false}) {
  // TODO(ahe): Can I move this to Scope or Prefix?
  if (declaration == other) return declaration;
  if (declaration is InvalidTypeDeclarationBuilder) return declaration;
  if (other is InvalidTypeDeclarationBuilder) return other;
  if (declaration is AccessErrorBuilder) {
    // Coverage-ignore-block(suite): Not run.
    AccessErrorBuilder error = declaration;
    declaration = error.builder;
  }
  if (other is AccessErrorBuilder) {
    // Coverage-ignore-block(suite): Not run.
    AccessErrorBuilder error = other;
    other = error.builder;
  }
  Builder? preferred;
  Uri? uri;
  Uri? otherUri;
  if (nameSpace.lookupLocalMember(name, setter: false) == declaration) {
    preferred = declaration;
  } else {
    uri = computeLibraryUri(declaration);
    otherUri = computeLibraryUri(other);
    if (declaration is LoadLibraryBuilder) {
      preferred = declaration;
    } else if (other is LoadLibraryBuilder) {
      preferred = other;
    } else if (otherUri.isScheme("dart") && !uri.isScheme("dart")) {
      preferred = declaration;
    } else if (uri.isScheme("dart") && !otherUri.isScheme("dart")) {
      preferred = other;
    }
  }
  if (preferred != null) {
    return preferred;
  }
  if (declaration.next == null && other.next == null) {
    if (isImport &&
        declaration is PrefixBuilder &&
        // Coverage-ignore(suite): Not run.
        other is PrefixBuilder) {
      // Coverage-ignore-block(suite): Not run.
      // Handles the case where the same prefix is used for different
      // imports.
      declaration.mergeScopes(other, problemReporting, nameSpace,
          uriOffset: uriOffset, isImport: isImport, isExport: isExport);
      return declaration;
    }
  }
  Uri firstUri = uri!;
  Uri secondUri = otherUri!;
  if (firstUri.toString().compareTo(secondUri.toString()) > 0) {
    firstUri = secondUri;
    secondUri = uri;
  }
  if (isExport) {
    Template<Message Function(String name, Uri uri, Uri uri2)> template =
        templateDuplicatedExport;
    Message message = template.withArguments(name, firstUri, secondUri);
    problemReporting.addProblem(
        message, uriOffset.fileOffset, noLength, uriOffset.uri);
  }
  Template<Message Function(String name, Uri uri, Uri uri2)> builderTemplate =
      isExport
          ? templateDuplicatedExportInType
          : templateDuplicatedImportInType;
  Message message = builderTemplate.withArguments(
      name,
      // TODO(ahe): We should probably use a context object here
      // instead of including URIs in this message.
      firstUri,
      secondUri);
  // We report the error lazily (setting suppressMessage to false) because the
  // spec 18.1 states that 'It is not an error if N is introduced by two or
  // more imports but never referred to.'
  return new InvalidTypeDeclarationBuilder(name,
      message.withLocation(uriOffset.uri, uriOffset.fileOffset, name.length),
      suppressMessage: false);
}

abstract class ProblemBuilder extends BuilderImpl {
  final String name;

  final Builder builder;

  @override
  final int charOffset;

  @override
  final Uri fileUri;

  ProblemBuilder(this.name, this.builder, this.charOffset, this.fileUri);

  @override
  bool get hasProblem => true;

  Message get message;

  @override
  String get fullNameForErrors => name;
}

/// Represents a [builder] that's being accessed incorrectly. For example, an
/// attempt to write to a final field, or to read from a setter.
class AccessErrorBuilder extends ProblemBuilder {
  AccessErrorBuilder(String name, Builder builder, int charOffset, Uri fileUri)
      : super(name, builder, charOffset, fileUri);

  @override
  Builder? get parent => builder.parent;

  @override
  // Coverage-ignore(suite): Not run.
  bool get isFinal => builder.isFinal;

  @override
  bool get isField => builder.isField;

  @override
  bool get isRegularMethod => builder.isRegularMethod;

  @override
  bool get isGetter => !builder.isGetter;

  @override
  bool get isSetter => !builder.isSetter;

  @override
  bool get isDeclarationInstanceMember => builder.isDeclarationInstanceMember;

  @override
  bool get isClassInstanceMember => builder.isClassInstanceMember;

  @override
  bool get isExtensionInstanceMember => builder.isExtensionInstanceMember;

  @override
  bool get isExtensionTypeInstanceMember =>
      builder.isExtensionTypeInstanceMember;

  @override
  bool get isStatic => builder.isStatic;

  @override
  // Coverage-ignore(suite): Not run.
  bool get isTopLevel => builder.isTopLevel;

  @override
  bool get isTypeDeclaration => builder.isTypeDeclaration;

  @override
  bool get isLocal => builder.isLocal;

  @override
  // Coverage-ignore(suite): Not run.
  Message get message => templateAccessError.withArguments(name);
}

class AmbiguousBuilder extends ProblemBuilder {
  AmbiguousBuilder(String name, Builder builder, int charOffset, Uri fileUri)
      : super(name, builder, charOffset, fileUri);

  @override
  // Coverage-ignore(suite): Not run.
  Builder? get parent => null;

  @override
  Message get message => templateDuplicatedDeclarationUse.withArguments(name);

  // Coverage-ignore(suite): Not run.
  // TODO(ahe): Also provide context.

  Builder getFirstDeclaration() {
    Builder declaration = builder;
    while (declaration.next != null) {
      declaration = declaration.next!;
    }
    return declaration;
  }
}

mixin ErroneousMemberBuilderMixin implements SourceMemberBuilder {
  @override
  // Coverage-ignore(suite): Not run.
  MemberDataForTesting? get dataForTesting => null;

  @override
  // Coverage-ignore(suite): Not run.
  Member get member => throw new UnsupportedError('$runtimeType.member');

  @override
  // Coverage-ignore(suite): Not run.
  Name get memberName => throw new UnsupportedError('$runtimeType.memberName');

  @override
  // Coverage-ignore(suite): Not run.
  Member? get readTarget => null;

  @override
  // Coverage-ignore(suite): Not run.
  Member? get writeTarget => null;

  @override
  // Coverage-ignore(suite): Not run.
  Member? get invokeTarget => null;

  @override
  // Coverage-ignore(suite): Not run.
  Iterable<Member> get exportedMembers => const [];

  @override
  // Coverage-ignore(suite): Not run.
  bool get isAssignable => false;

  @override
  // Coverage-ignore(suite): Not run.
  bool get isExternal => false;

  @override
  // Coverage-ignore(suite): Not run.
  bool get isAbstract => false;

  @override
  bool get isConflictingSetter => false;

  @override
  bool get isConflictingAugmentationMember => false;

  @override
  void set isConflictingAugmentationMember(bool value) {
    throw new UnsupportedError('$runtimeType.isConflictingAugmentationMember=');
  }

  @override
  void set parent(Builder? value) {
    throw new UnsupportedError('$runtimeType.parent=');
  }

  @override
  DeclarationBuilder get declarationBuilder {
    throw new UnsupportedError('$runtimeType.declarationBuilder');
  }

  @override
  ClassBuilder get classBuilder {
    throw new UnsupportedError('$runtimeType.classBuilder');
  }

  @override
  SourceLibraryBuilder get libraryBuilder {
    throw new UnsupportedError('$runtimeType.library');
  }

  // TODO(johnniwinther): Remove this and create a [ProcedureBuilder] interface.
  @override
  // Coverage-ignore(suite): Not run.
  ProcedureKind? get kind => null;

  @override
  void buildOutlineExpressions(
      ClassHierarchy classHierarchy,
      List<DelayedActionPerformer> delayedActionPerformers,
      List<DelayedDefaultValueCloner> delayedDefaultValueCloners) {
    throw new UnsupportedError('$runtimeType.buildOutlineExpressions');
  }

  @override
  // Coverage-ignore(suite): Not run.
  void buildOutlineNodes(BuildNodesCallback f) {
    assert(false, "Unexpected call to $runtimeType.buildOutlineNodes.");
  }

  @override
  // Coverage-ignore(suite): Not run.
  int buildBodyNodes(BuildNodesCallback f) {
    assert(false, "Unexpected call to $runtimeType.buildBodyNodes.");
    return 0;
  }

  @override
  // Coverage-ignore(suite): Not run.
  List<ClassMember> get localMembers => const <ClassMember>[];

  @override
  // Coverage-ignore(suite): Not run.
  List<ClassMember> get localSetters => const <ClassMember>[];

  @override
  // Coverage-ignore(suite): Not run.
  void checkVariance(
      SourceClassBuilder sourceClassBuilder, TypeEnvironment typeEnvironment) {
    assert(false, "Unexpected call to $runtimeType.checkVariance.");
  }

  @override
  // Coverage-ignore(suite): Not run.
  void checkTypes(
      SourceLibraryBuilder library, TypeEnvironment typeEnvironment) {
    assert(false, "Unexpected call to $runtimeType.checkVariance.");
  }

  @override
  bool get isAugmentation {
    throw new UnsupportedError('$runtimeType.isAugmentation');
  }

  @override
  AugmentSuperTarget? get augmentSuperTarget {
    throw new UnsupportedError('$runtimeType.augmentSuperTarget}');
  }

  @override
  BodyBuilderContext createBodyBuilderContext(
      {required bool inOutlineBuildingPhase,
      required bool inMetadata,
      required bool inConstFields}) {
    throw new UnsupportedError(
        '$runtimeType.bodyBuilderContextForAnnotations}');
  }

  @override
  Iterable<Annotatable> get annotatables {
    throw new UnsupportedError('$runtimeType.annotatables}');
  }
}

class AmbiguousMemberBuilder extends AmbiguousBuilder
    with ErroneousMemberBuilderMixin {
  AmbiguousMemberBuilder(
      String name, Builder builder, int charOffset, Uri fileUri)
      : super(name, builder, charOffset, fileUri);
}

/// Iterator over builders mapped in a [Scope], including duplicates for each
/// directly mapped builder.
class ScopeIterator implements Iterator<Builder> {
  Iterator<Builder>? local;
  Iterator<Builder>? setters;
  Iterator<Builder>? extensions;

  Builder? _current;

  ScopeIterator.fromIterators(this.local, this.setters, this.extensions);

  ScopeIterator(Scope scope)
      : this.fromIterators(scope._local?.values.iterator,
            scope._setters?.values.iterator, scope._extensions?.iterator);

  @override
  bool moveNext() {
    Builder? next = _current?.next;
    if (next != null) {
      _current = next;
      return true;
    }
    if (local != null) {
      if (local!.moveNext()) {
        _current = local!.current;
        return true;
      }
      local = null;
    }
    if (setters != null) {
      if (setters!.moveNext()) {
        _current = setters!.current;
        return true;
      }
      setters = null;
    }
    if (extensions != null) {
      while (extensions!.moveNext()) {
        Builder extension = extensions!.current;
        // Named extensions have already been included throw [local] so we skip
        // them here.
        if (extension is SourceExtensionBuilder &&
            extension.isUnnamedExtension) {
          _current = extension;
          return true;
        }
      }
      extensions = null;
    }
    _current = null;
    return false;
  }

  @override
  Builder get current {
    return _current ?? // Coverage-ignore(suite): Not run.
        (throw new StateError('No element'));
  }
}

/// Iterator over builders mapped in a [Scope], including duplicates for each
/// directly mapped builder.
///
/// Compared to [ScopeIterator] this iterator also gives
/// access to the name that the builders are mapped to.
class ScopeNameIterator extends ScopeIterator implements NameIterator<Builder> {
  Iterator<String>? localNames;
  Iterator<String>? setterNames;

  String? _name;

  ScopeNameIterator.fromIterators(Map<String, Builder>? getables,
      Map<String, Builder>? setables, Iterator<Builder>? extensions)
      : localNames = getables?.keys.iterator,
        setterNames = setables?.keys.iterator,
        super.fromIterators(
            getables?.values.iterator, setables?.values.iterator, extensions);

  ScopeNameIterator(Scope scope)
      : localNames = scope._local?.keys.iterator,
        setterNames = scope._setters?.keys.iterator,
        super(scope);

  @override
  bool moveNext() {
    Builder? next = _current?.next;
    if (next != null) {
      _current = next;
      return true;
    }
    if (local != null) {
      if (local!.moveNext()) {
        localNames!.moveNext();
        _current = local!.current;
        _name = localNames!.current;
        return true;
      }
      local = null;
      localNames = null;
    }
    if (setters != null) {
      if (setters!.moveNext()) {
        setterNames!.moveNext();
        _current = setters!.current;
        _name = setterNames!.current;
        return true;
      }
      setters = null;
      setterNames = null;
    }
    if (extensions != null) {
      while (extensions!.moveNext()) {
        Builder extension = extensions!.current;
        // Named extensions have already been included throw [local] so we skip
        // them here.
        if (extension is SourceExtensionBuilder &&
            extension.isUnnamedExtension) {
          _current = extension;
          _name = extension.name;
          return true;
        }
      }
      extensions = null;
    }
    _current = null;
    _name = null;
    return false;
  }

  @override
  String get name {
    return _name ?? // Coverage-ignore(suite): Not run.
        (throw new StateError('No element'));
  }
}

/// Iterator over builders mapped in a [ConstructorScope], including duplicates
/// for each directly mapped builder.
class ConstructorScopeIterator implements Iterator<MemberBuilder> {
  Iterator<MemberBuilder> local;

  MemberBuilder? _current;

  ConstructorScopeIterator(ConstructorScope scope)
      : local = scope._local.values.iterator;

  @override
  bool moveNext() {
    MemberBuilder? next = _current?.next as MemberBuilder?;
    if (next != null) {
      _current = next;
      return true;
    }
    if (local.moveNext()) {
      _current = local.current;
      return true;
    }
    return false;
  }

  @override
  MemberBuilder get current {
    return _current ?? // Coverage-ignore(suite): Not run.
        (throw new StateError('No element'));
  }
}

/// Iterator over builders mapped in a [ConstructorScope], including duplicates
/// for each directly mapped builder.
///
/// Compared to [ConstructorScopeIterator] this iterator also gives
/// access to the name that the builders are mapped to.
class ConstructorScopeNameIterator extends ConstructorScopeIterator
    implements NameIterator<MemberBuilder> {
  final Iterator<String> localNames;

  String? _name;

  ConstructorScopeNameIterator(ConstructorScope scope)
      : localNames = scope._local.keys.iterator,
        super(scope);

  @override
  bool moveNext() {
    MemberBuilder? next = _current?.next as MemberBuilder?;
    if (next != null) {
      _current = next;
      return true;
    }
    if (local.moveNext()) {
      localNames.moveNext();
      _current = local.current;
      _name = localNames.current;
      return true;
    }
    _current = null;
    _name = null;
    return false;
  }

  @override
  String get name {
    return _name ?? // Coverage-ignore(suite): Not run.
        (throw new StateError('No element'));
  }
}

/// Filtered builder [Iterator].
class FilteredIterator<T extends Builder> implements Iterator<T> {
  final Iterator<Builder> _iterator;
  final Builder? parent;
  final bool includeDuplicates;
  final bool includeAugmentations;

  FilteredIterator(this._iterator,
      {required this.parent,
      required this.includeDuplicates,
      required this.includeAugmentations});

  bool _include(Builder element) {
    if (parent != null && element.parent != parent) return false;
    if (!includeDuplicates &&
        (element.isDuplicate || element.isConflictingAugmentationMember)) {
      return false;
    }
    if (!includeAugmentations && element.isAugmenting) return false;
    return element is T;
  }

  @override
  T get current => _iterator.current as T;

  @override
  bool moveNext() {
    while (_iterator.moveNext()) {
      Builder candidate = _iterator.current;
      if (_include(candidate)) {
        return true;
      }
    }
    return false;
  }
}

/// Filtered [NameIterator].
///
/// Compared to [FilteredIterator] this iterator also gives
/// access to the name that the builders are mapped to.
class FilteredNameIterator<T extends Builder> implements NameIterator<T> {
  final NameIterator<Builder> _iterator;
  final Builder? parent;
  final bool includeDuplicates;
  final bool includeAugmentations;

  FilteredNameIterator(this._iterator,
      {required this.parent,
      required this.includeDuplicates,
      required this.includeAugmentations});

  bool _include(Builder element) {
    if (parent != null && element.parent != parent) return false;
    if (!includeDuplicates &&
        (element.isDuplicate || element.isConflictingAugmentationMember)) {
      return false;
    }
    if (!includeAugmentations && element.isAugmenting) return false;
    return element is T;
  }

  @override
  T get current => _iterator.current as T;

  @override
  String get name => _iterator.name;

  @override
  bool moveNext() {
    while (_iterator.moveNext()) {
      Builder candidate = _iterator.current;
      if (_include(candidate)) {
        return true;
      }
    }
    return false;
  }
}

extension IteratorExtension<T extends Builder> on Iterator<T> {
  void forEach(void Function(T) f) {
    while (moveNext()) {
      f(current);
    }
  }

  // Coverage-ignore(suite): Not run.
  List<T> toList() {
    List<T> list = [];
    while (moveNext()) {
      list.add(current);
    }
    return list;
  }

  Iterator<T> join(Iterator<T> other) {
    return new IteratorSequence<T>([this, other]);
  }
}

extension NameIteratorExtension<T extends Builder> on NameIterator<T> {
  void forEach(void Function(String, T) f) {
    while (moveNext()) {
      f(name, current);
    }
  }
}

abstract class MergedScope<T extends Builder> {
  final T _origin;
  final NameSpace _originNameSpace;
  Map<T, NameSpace> _augmentationNameSpaces = {};

  MergedScope(this._origin, this._originNameSpace);

  SourceLibraryBuilder get originLibrary;

  void _addBuilderToMergedScope(
      String name, Builder newBuilder, Builder? existingBuilder,
      {required bool setter, required bool inPatchLibrary}) {
    bool isAugmentationBuilder = inPatchLibrary
        ? newBuilder.hasPatchAnnotation
        : newBuilder.isAugmentation;
    if (existingBuilder != null) {
      if (isAugmentationBuilder) {
        existingBuilder.applyAugmentation(newBuilder);
      } else {
        newBuilder.isConflictingAugmentationMember = true;
        Message message;
        Message context;
        if (newBuilder is SourceMemberBuilder &&
            existingBuilder is SourceMemberBuilder) {
          if (_origin is SourceLibraryBuilder) {
            message = inPatchLibrary
                ? templateNonPatchLibraryMemberConflict.withArguments(name)
                : templateNonAugmentationLibraryMemberConflict
                    .withArguments(name);
          } else {
            message = inPatchLibrary
                ? templateNonPatchClassMemberConflict.withArguments(name)
                : templateNonAugmentationClassMemberConflict
                    .withArguments(name);
          }
          context = messageNonAugmentationMemberConflictCause;
        } else if (newBuilder is SourceClassBuilder &&
            existingBuilder is SourceClassBuilder) {
          message = inPatchLibrary
              ? templateNonPatchClassConflict.withArguments(name)
              : templateNonAugmentationClassConflict.withArguments(name);
          context = messageNonAugmentationClassConflictCause;
        } else {
          if (_origin is SourceLibraryBuilder) {
            message = inPatchLibrary
                ? templateNonPatchLibraryConflict.withArguments(name)
                : templateNonAugmentationLibraryConflict.withArguments(name);
          } else {
            // Coverage-ignore-block(suite): Not run.
            message = inPatchLibrary
                ? templateNonPatchClassMemberConflict.withArguments(name)
                : templateNonAugmentationClassMemberConflict
                    .withArguments(name);
          }
          context = messageNonAugmentationMemberConflictCause;
        }
        originLibrary.addProblem(
            message, newBuilder.charOffset, name.length, newBuilder.fileUri,
            context: [
              context.withLocation(existingBuilder.fileUri!,
                  existingBuilder.charOffset, name.length)
            ]);
      }
    } else {
      if (isAugmentationBuilder) {
        Message message;
        if (newBuilder is SourceMemberBuilder) {
          if (_origin is SourceLibraryBuilder) {
            message = inPatchLibrary
                ? templateUnmatchedPatchLibraryMember.withArguments(name)
                : templateUnmatchedAugmentationLibraryMember
                    .withArguments(name);
          } else {
            message = inPatchLibrary
                ? templateUnmatchedPatchClassMember.withArguments(name)
                : templateUnmatchedAugmentationClassMember.withArguments(name);
          }
        } else if (newBuilder is SourceClassBuilder) {
          message = inPatchLibrary
              ? templateUnmatchedPatchClass.withArguments(name)
              : templateUnmatchedAugmentationClass.withArguments(name);
        } else {
          message = inPatchLibrary
              ? templateUnmatchedPatchDeclaration.withArguments(name)
              :
              // Coverage-ignore(suite): Not run.
              templateUnmatchedAugmentationDeclaration.withArguments(name);
        }
        originLibrary.addProblem(
            message, newBuilder.charOffset, name.length, newBuilder.fileUri);
      } else {
        if (inPatchLibrary &&
            !name.startsWith('_') &&
            !_allowInjectedPublicMember(newBuilder)) {
          originLibrary.addProblem(
              templatePatchInjectionFailed.withArguments(
                  name, originLibrary.importUri),
              newBuilder.charOffset,
              noLength,
              newBuilder.fileUri);
        }
        _originNameSpace.addLocalMember(name, newBuilder, setter: setter);
        if (newBuilder is ExtensionBuilder) {
          _originNameSpace.addExtension(newBuilder);
        }
        for (NameSpace augmentationNameSpace
            in _augmentationNameSpaces.values) {
          _addBuilderToAugmentationNameSpace(
              augmentationNameSpace, name, newBuilder,
              setter: setter);
        }
      }
    }
  }

  void _addBuilderToAugmentationNameSpace(
      NameSpace augmentationNameSpace, String name, Builder member,
      {required bool setter}) {
    Builder? augmentationMember =
        augmentationNameSpace.lookupLocalMember(name, setter: setter);
    if (augmentationMember == null) {
      augmentationNameSpace.addLocalMember(name, member, setter: setter);
      if (member is ExtensionBuilder) {
        augmentationNameSpace.addExtension(member);
      }
    }
  }

  void _addAugmentationScope(T parentBuilder, NameSpace nameSpace,
      {required Map<String, List<Builder>>? augmentations,
      required Map<String, List<Builder>>? setterAugmentations,
      required bool inPatchLibrary}) {
    // TODO(johnniwinther): Use `scope.filteredNameIterator` instead of
    // `scope.forEachLocalMember`/`scope.forEachLocalSetter`.

    // Include all augmentation scope members to the origin scope.
    nameSpace.forEachLocalMember((String name, Builder member) {
      // In case of duplicates we use the first declaration.
      while (member.isDuplicate) {
        member = member.next!;
      }
      _addBuilderToMergedScope(
          name, member, _originNameSpace.lookupLocalMember(name, setter: false),
          setter: false, inPatchLibrary: inPatchLibrary);
    });
    if (augmentations != null) {
      for (String augmentedName in augmentations.keys) {
        for (Builder augmentation in augmentations[augmentedName]!) {
          _addBuilderToMergedScope(augmentedName, augmentation,
              _originNameSpace.lookupLocalMember(augmentedName, setter: false),
              setter: false, inPatchLibrary: inPatchLibrary);
        }
      }
    }
    nameSpace.forEachLocalSetter((String name, Builder member) {
      // In case of duplicates we use the first declaration.
      while (member.isDuplicate) {
        member = member.next!;
      }
      _addBuilderToMergedScope(
          name, member, _originNameSpace.lookupLocalMember(name, setter: true),
          setter: true, inPatchLibrary: inPatchLibrary);
    });
    if (setterAugmentations != null) {
      for (String augmentedName in setterAugmentations.keys) {
        for (Builder augmentation in setterAugmentations[augmentedName]!) {
          _addBuilderToMergedScope(augmentedName, augmentation,
              _originNameSpace.lookupLocalMember(augmentedName, setter: true),
              setter: true, inPatchLibrary: inPatchLibrary);
        }
      }
    }
    nameSpace.forEachLocalExtension((ExtensionBuilder extensionBuilder) {
      if (extensionBuilder is SourceExtensionBuilder &&
          extensionBuilder.isUnnamedExtension) {
        _originNameSpace.addExtension(extensionBuilder);
        for (NameSpace augmentationNameSpace
            in _augmentationNameSpaces.values) {
          augmentationNameSpace.addExtension(extensionBuilder);
        }
      }
    });

    // Include all origin scope members in the augmentation scope.
    _originNameSpace.forEachLocalMember((String name, Builder originMember) {
      _addBuilderToAugmentationNameSpace(nameSpace, name, originMember,
          setter: false);
    });
    _originNameSpace.forEachLocalSetter((String name, Builder originMember) {
      _addBuilderToAugmentationNameSpace(nameSpace, name, originMember,
          setter: true);
    });
    _originNameSpace.forEachLocalExtension((ExtensionBuilder extensionBuilder) {
      if (extensionBuilder is SourceExtensionBuilder &&
          extensionBuilder.isUnnamedExtension) {
        nameSpace.addExtension(extensionBuilder);
      }
    });

    _augmentationNameSpaces[parentBuilder] = nameSpace;
  }

  bool _allowInjectedPublicMember(Builder newBuilder);
}

class MergedLibraryScope extends MergedScope<SourceLibraryBuilder> {
  MergedLibraryScope(SourceLibraryBuilder origin) : super(origin, origin.scope);

  @override
  SourceLibraryBuilder get originLibrary => _origin;

  void addAugmentationScope(SourceLibraryBuilder builder) {
    _addAugmentationScope(builder, builder.scope,
        augmentations: builder.scope.augmentations,
        setterAugmentations: builder.scope.setterAugmentations,
        inPatchLibrary: builder.isPatchLibrary);
  }

  @override
  bool _allowInjectedPublicMember(Builder newBuilder) {
    return originLibrary.importUri.isScheme("dart") &&
        originLibrary.importUri.path.startsWith("_");
  }
}

class MergedClassMemberScope extends MergedScope<SourceClassBuilder> {
  final ConstructorScope _originConstructorScope;
  Map<SourceClassBuilder, ConstructorScope> _augmentationConstructorScopes = {};

  MergedClassMemberScope(SourceClassBuilder origin)
      : _originConstructorScope = origin.constructorScope,
        super(origin, origin.scope);

  @override
  SourceLibraryBuilder get originLibrary => _origin.libraryBuilder;

  void _addAugmentationConstructorScope(ConstructorScope constructorScope,
      {required bool inPatchLibrary}) {
    constructorScope._local
        .forEach((String name, MemberBuilder newConstructor) {
      MemberBuilder? existingConstructor =
          _originConstructorScope.lookupLocalMember(name);
      bool isAugmentationBuilder = inPatchLibrary
          ? newConstructor.hasPatchAnnotation
          : newConstructor.isAugmentation;
      if (existingConstructor != null) {
        if (isAugmentationBuilder) {
          existingConstructor.applyAugmentation(newConstructor);
        } else {
          newConstructor.isConflictingAugmentationMember = true;
          originLibrary.addProblem(
              inPatchLibrary
                  ? templateNonPatchConstructorConflict
                      .withArguments(newConstructor.fullNameForErrors)
                  :
                  // Coverage-ignore(suite): Not run.
                  templateNonAugmentationConstructorConflict
                      .withArguments(newConstructor.fullNameForErrors),
              newConstructor.charOffset,
              noLength,
              newConstructor.fileUri,
              context: [
                messageNonAugmentationConstructorConflictCause.withLocation(
                    existingConstructor.fileUri!,
                    existingConstructor.charOffset,
                    noLength)
              ]);
        }
      } else {
        if (isAugmentationBuilder) {
          originLibrary.addProblem(
              inPatchLibrary
                  ? templateUnmatchedPatchConstructor
                      .withArguments(newConstructor.fullNameForErrors)
                  :
                  // Coverage-ignore(suite): Not run.
                  templateUnmatchedAugmentationConstructor
                      .withArguments(newConstructor.fullNameForErrors),
              newConstructor.charOffset,
              noLength,
              newConstructor.fileUri);
        } else {
          _originConstructorScope.addLocalMember(name, newConstructor);
          for (ConstructorScope augmentationConstructorScope
              in _augmentationConstructorScopes.values) {
            // Coverage-ignore-block(suite): Not run.
            _addConstructorToAugmentationScope(
                augmentationConstructorScope, name, newConstructor);
          }
        }
        if (inPatchLibrary &&
            !name.startsWith('_') &&
            !_allowInjectedPublicMember(newConstructor)) {
          // Coverage-ignore-block(suite): Not run.
          originLibrary.addProblem(
              templatePatchInjectionFailed.withArguments(
                  name, originLibrary.importUri),
              newConstructor.charOffset,
              noLength,
              newConstructor.fileUri);
        }
      }
    });
    _originConstructorScope._local
        .forEach((String name, MemberBuilder originConstructor) {
      _addConstructorToAugmentationScope(
          constructorScope, name, originConstructor);
    });
  }

  void _addConstructorToAugmentationScope(
      ConstructorScope augmentationConstructorScope,
      String name,
      MemberBuilder constructor) {
    Builder? augmentationConstructor =
        augmentationConstructorScope.lookupLocalMember(name);
    if (augmentationConstructor == null) {
      augmentationConstructorScope.addLocalMember(name, constructor);
    }
  }

  // TODO(johnniwinther): Check for conflicts between constructors and class
  //  members.
  void addAugmentationScope(SourceClassBuilder builder) {
    _addAugmentationScope(builder, builder.scope,
        augmentations: builder.scope.augmentations,
        setterAugmentations: builder.scope.setterAugmentations,
        inPatchLibrary: builder.libraryBuilder.isPatchLibrary);
    _addAugmentationConstructorScope(builder.constructorScope,
        inPatchLibrary: builder.libraryBuilder.isPatchLibrary);
  }

  @override
  bool _allowInjectedPublicMember(Builder newBuilder) {
    if (originLibrary.importUri.isScheme("dart") &&
        originLibrary.importUri.path.startsWith("_")) {
      return true;
    }
    if (newBuilder.isStatic) {
      // Coverage-ignore-block(suite): Not run.
      return _origin.name.startsWith('_');
    }
    // TODO(johnniwinther): Restrict the use of injected public class members.
    return true;
  }
}

extension on Builder {
  bool get isAugmentation {
    Builder self = this;
    if (self is SourceLibraryBuilder) {
      // Coverage-ignore-block(suite): Not run.
      return self.isAugmentationLibrary;
    } else if (self is SourceClassBuilder) {
      return self.isAugmentation;
    } else if (self is SourceMemberBuilder) {
      return self.isAugmentation;
    } else {
      // TODO(johnniwinther): Handle all cases here.
      return false;
    }
  }

  bool get isConflictingAugmentationMember {
    Builder self = this;
    if (self is SourceMemberBuilder) {
      return self.isConflictingAugmentationMember;
    } else if (self is SourceClassBuilder) {
      return self.isConflictingAugmentationMember;
    }
    // TODO(johnniwinther): Handle all cases here.
    return false;
  }

  void set isConflictingAugmentationMember(bool value) {
    Builder self = this;
    if (self is SourceMemberBuilder) {
      self.isConflictingAugmentationMember = value;
    } else if (self is SourceClassBuilder) {
      self.isConflictingAugmentationMember = value;
    }
    // TODO(johnniwinther): Handle all cases here.
  }

  bool _hasPatchAnnotation(List<MetadataBuilder>? metadata) {
    if (metadata == null) {
      return false;
    }
    for (MetadataBuilder metadataBuilder in metadata) {
      if (metadataBuilder.hasPatch) {
        return true;
      }
    }
    return false;
  }

  bool get hasPatchAnnotation {
    Builder self = this;
    if (self is SourceFunctionBuilder) {
      return _hasPatchAnnotation(self.metadata);
    } else if (self is SourceClassBuilder) {
      return _hasPatchAnnotation(self.metadata);
    } else if (self is SourceExtensionBuilder) {
      return _hasPatchAnnotation(self.metadata);
    } else if (self is SourceExtensionTypeDeclarationBuilder) {
      // Coverage-ignore-block(suite): Not run.
      return _hasPatchAnnotation(self.metadata);
    }
    return false;
  }
}

class IteratorSequence<T> implements Iterator<T> {
  Iterator<Iterator<T>> _iterators;

  Iterator<T>? _current;

  IteratorSequence(Iterable<Iterator<T>> iterators)
      : _iterators = iterators.iterator;

  @override
  T get current {
    if (_current != null) {
      return _current!.current;
    }
    // Coverage-ignore-block(suite): Not run.
    throw new StateError("No current element");
  }

  @override
  bool moveNext() {
    if (_current != null) {
      if (_current!.moveNext()) {
        return true;
      }
      _current = null;
    }
    while (_iterators.moveNext()) {
      _current = _iterators.current;
      if (_current!.moveNext()) {
        return true;
      }
      _current = null;
    }
    return false;
  }
}
