// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:typed_data';

import 'package:analyzer/dart/analysis/declared_variables.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/context/context.dart';
import 'package:analyzer/src/dart/analysis/file_state.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/inheritance_manager3.dart';
import 'package:analyzer/src/dart/element/name_union.dart';
import 'package:analyzer/src/summary2/bundle_writer.dart';
import 'package:analyzer/src/summary2/detach_nodes.dart';
import 'package:analyzer/src/summary2/library_builder.dart';
import 'package:analyzer/src/summary2/linked_element_factory.dart';
import 'package:analyzer/src/summary2/macro_application.dart';
import 'package:analyzer/src/summary2/macro_declarations.dart';
import 'package:analyzer/src/summary2/reference.dart';
import 'package:analyzer/src/summary2/simply_bounded.dart';
import 'package:analyzer/src/summary2/super_constructor_resolver.dart';
import 'package:analyzer/src/summary2/top_level_inference.dart';
import 'package:analyzer/src/summary2/type_alias.dart';
import 'package:analyzer/src/summary2/types_builder.dart';
import 'package:analyzer/src/summary2/variance_builder.dart';
import 'package:analyzer/src/util/performance/operation_performance.dart';
import 'package:analyzer/src/utilities/extensions/collection.dart';
import 'package:analyzer/src/utilities/uri_cache.dart';
import 'package:macros/src/executor/multi_executor.dart' as macro;

Future<LinkResult> link({
  required LinkedElementFactory elementFactory,
  required OperationPerformanceImpl performance,
  required List<LibraryFileKind> inputLibraries,
  required Map<LibraryFileKind, MacroResultInput> inputMacroResults,
  macro.MultiMacroExecutor? macroExecutor,
}) async {
  var linker = Linker(elementFactory, macroExecutor);
  await linker.link(
    performance: performance,
    inputLibraries: inputLibraries,
    inputMacroResults: inputMacroResults,
  );

  var macroResultsOutput = <MacroResultOutput>[];
  for (var builder in linker.builders.values) {
    var result = builder.getCacheableMacroResult();
    macroResultsOutput.addIfNotNull(result);
  }

  return LinkResult(
    resolutionBytes: linker.resolutionBytes,
    macroResults: macroResultsOutput,
  );
}

class Linker {
  final LinkedElementFactory elementFactory;
  final macro.MultiMacroExecutor? macroExecutor;
  late final DeclarationBuilder macroDeclarationBuilder;

  /// Libraries that are being linked.
  final Map<Uri, LibraryBuilder> builders = {};

  final Map<ElementImpl, ast.AstNode> elementNodes = Map.identity();

  late InheritanceManager3 inheritance; // TODO(scheglov): cache it

  late Uint8List resolutionBytes;

  LibraryMacroApplier? _macroApplier;

  Linker(this.elementFactory, this.macroExecutor) {
    macroDeclarationBuilder = DeclarationBuilder(
      elementFactory: elementFactory,
      nodeOfElement: (element) => elementNodes[element],
    );
  }

  AnalysisContextImpl get analysisContext {
    return elementFactory.analysisContext;
  }

  DeclaredVariables get declaredVariables {
    return analysisContext.declaredVariables;
  }

  LibraryMacroApplier? get macroApplier => _macroApplier;

  Reference get rootReference => elementFactory.rootReference;

  bool get _isLinkingDartCore {
    var dartCoreUri = uriCache.parse('dart:core');
    return builders.containsKey(dartCoreUri);
  }

  /// If the [element] is part of a library being linked, return the node
  /// from which it was created.
  ast.AstNode? getLinkingNode(Element element) {
    return elementNodes[element];
  }

  Future<void> link({
    required OperationPerformanceImpl performance,
    required List<LibraryFileKind> inputLibraries,
    required Map<LibraryFileKind, MacroResultInput> inputMacroResults,
  }) async {
    performance.run('LibraryBuilder.build', (performance) {
      for (var inputLibrary in inputLibraries) {
        var inputMacroResult = inputMacroResults[inputLibrary];
        LibraryBuilder.build(
          linker: this,
          inputLibrary: inputLibrary,
          inputMacroResult: inputMacroResult,
          performance: performance,
        );
      }
    });

    await performance.runAsync('buildOutlines', (performance) async {
      await _buildOutlines(
        performance: performance,
      );
    });

    performance.run('writeLibraries', (performance) {
      _writeLibraries(
        performance: performance,
      );
    });
  }

  void _buildClassSyntheticConstructors() {
    for (var library in builders.values) {
      library.buildClassSyntheticConstructors();
    }
  }

  void _buildElementNameUnions() {
    for (var builder in builders.values) {
      var element = builder.element;
      element.nameUnion = ElementNameUnion.forLibrary(element);
    }
  }

  void _buildEnumChildren() {
    for (var library in builders.values) {
      library.buildEnumChildren();
    }
  }

  void _buildEnumSyntheticConstructors() {
    for (var library in builders.values) {
      library.buildEnumSyntheticConstructors();
    }
  }

  void _buildExportScopes() {
    for (var library in builders.values) {
      library.buildInitialExportScope();
    }

    var exportingBuilders = <LibraryBuilder>{};
    var exportedBuilders = <LibraryBuilder>{};

    for (var library in builders.values) {
      library.addExporters();
    }

    for (var library in builders.values) {
      if (library.exports.isNotEmpty) {
        exportedBuilders.add(library);
        for (var export in library.exports) {
          exportingBuilders.add(export.exporter);
        }
      }
    }

    var both = <LibraryBuilder>{};
    for (var exported in exportedBuilders) {
      if (exportingBuilders.contains(exported)) {
        both.add(exported);
      }
      for (var export in exported.exports) {
        exported.exportScope.forEach(export.addToExportScope);
      }
    }

    while (true) {
      var hasChanges = false;
      for (var exported in both) {
        for (var export in exported.exports) {
          exported.exportScope.forEach((name, reference) {
            if (export.addToExportScope(name, reference)) {
              hasChanges = true;
            }
          });
        }
      }
      if (!hasChanges) break;
    }

    for (var library in builders.values) {
      library.storeExportScope();
    }
  }

  Future<LibraryMacroApplier?> _buildMacroApplier() async {
    var macroExecutor = this.macroExecutor;
    if (macroExecutor == null) {
      return null;
    }

    var macroApplier = LibraryMacroApplier(
      elementFactory: elementFactory,
      macroExecutor: macroExecutor,
      isLibraryBeingLinked: (uri) => builders.containsKey(uri),
      declarationBuilder: macroDeclarationBuilder,
      runDeclarationsPhase: _executeMacroDeclarationsPhase,
    );

    for (var library in builders.values) {
      if (library.inputMacroPartInclude == null) {
        await library.fillMacroApplier(macroApplier);
      }
    }

    return _macroApplier = macroApplier;
  }

  Future<void> _buildOutlines({
    required OperationPerformanceImpl performance,
  }) async {
    _createTypeSystemIfNotLinkingDartCore();

    await performance.runAsync(
      'computeLibraryScopes',
      (performance) async {
        await _computeLibraryScopes(
          performance: performance,
        );
      },
    );

    _createTypeSystem();
    _resolveTypes();
    _setDefaultSupertypes();

    await performance.runAsync(
      'executeMacroDeclarationsPhase',
      (performance) async {
        await _executeMacroDeclarationsPhase(
          targetElement: null,
          performance: performance,
        );
      },
    );

    _buildClassSyntheticConstructors();
    _buildEnumSyntheticConstructors();
    _replaceConstFieldsIfNoConstConstructor();
    _resolveConstructorFieldFormals();
    _buildEnumChildren();
    _computeFieldPromotability();
    SuperConstructorResolver(this).perform();
    _performTopLevelInference();
    _resolveConstructors();
    _resolveConstantInitializers();
    _resolveDefaultValues();
    _resolveMetadata();

    // TODO(scheglov): verify if any resolutions should happen after
    await performance.runAsync(
      'executeMacroDefinitionsPhase',
      (performance) async {
        await _executeMacroDefinitionsPhase(
          performance: performance,
        );
      },
    );

    _collectMixinSuperInvokedNames();
    _buildElementNameUnions();
    _detachNodes();

    await performance.runAsync(
      'mergeMacroAugmentations',
      (performance) async {
        await _mergeMacroAugmentations(
          performance: performance,
        );
      },
    );

    _disposeMacroApplications();
    for (var library in builders.values) {
      library.updateInputMacroAugmentation();
    }
  }

  void _collectMixinSuperInvokedNames() {
    for (var library in builders.values) {
      library.collectMixinSuperInvokedNames();
    }
  }

  void _computeFieldPromotability() {
    for (var library in builders.values) {
      library.computeFieldPromotability();
    }
  }

  Future<void> _computeLibraryScopes({
    required OperationPerformanceImpl performance,
  }) async {
    for (var library in builders.values) {
      library.buildElements();
    }

    await performance.runAsync(
      'buildMacroApplier',
      (performance) async {
        await _buildMacroApplier();
      },
    );

    // The macro types phase can resolve exported identifier.
    _buildExportScopes();

    await performance.runAsync(
      'executeMacroTypesPhase',
      (performance) async {
        for (var library in builders.values) {
          await library.executeMacroTypesPhase(
            performance: performance,
          );
        }
      },
    );

    _buildExportScopes();
  }

  void _createTypeSystem() {
    elementFactory.createTypeProviders(
      elementFactory.dartCoreElement,
      elementFactory.dartAsyncElement,
    );

    inheritance = InheritanceManager3();
  }

  /// To resolve macro annotations we need to access exported namespaces of
  /// imported (and already linked) libraries. While computing it we might
  /// need `Null` from `dart:core` (to convert null safe types to legacy).
  void _createTypeSystemIfNotLinkingDartCore() {
    if (!_isLinkingDartCore) {
      _createTypeSystem();
    }
  }

  void _detachNodes() {
    for (var builder in builders.values) {
      detachElementsFromNodes(builder.element);
    }
  }

  void _disposeMacroApplications() {
    for (var library in builders.values) {
      library.disposeMacroApplications();
    }
  }

  Future<void> _executeMacroDeclarationsPhase({
    required ElementImpl? targetElement,
    required OperationPerformanceImpl performance,
  }) async {
    while (true) {
      var hasProgress = false;
      for (var library in builders.values) {
        var stepResult = await library.executeMacroDeclarationsPhase(
          targetElement: targetElement,
          performance: performance,
        );
        switch (stepResult) {
          case MacroDeclarationsPhaseStepResult.nothing:
            break;
          case MacroDeclarationsPhaseStepResult.otherProgress:
            hasProgress = true;
          case MacroDeclarationsPhaseStepResult.topDeclaration:
            hasProgress = true;
            _buildExportScopes();
        }
      }
      if (!hasProgress) {
        break;
      }
    }
  }

  Future<void> _executeMacroDefinitionsPhase({
    required OperationPerformanceImpl performance,
  }) async {
    for (var library in builders.values) {
      await library.executeMacroDefinitionsPhase(
        performance: performance,
      );
    }
  }

  Future<void> _mergeMacroAugmentations({
    required OperationPerformanceImpl performance,
  }) async {
    for (var library in builders.values) {
      await library.mergeMacroAugmentations(
        performance: performance,
      );
    }
  }

  void _performTopLevelInference() {
    TopLevelInference(this).infer();
  }

  void _replaceConstFieldsIfNoConstConstructor() {
    for (var library in builders.values) {
      library.replaceConstFieldsIfNoConstConstructor();
    }
  }

  void _resolveConstantInitializers() {
    ConstantInitializersResolver(this).perform();
  }

  void _resolveConstructorFieldFormals() {
    for (var library in builders.values) {
      library.resolveConstructorFieldFormals();
    }
  }

  void _resolveConstructors() {
    for (var library in builders.values) {
      library.resolveConstructors();
    }
  }

  void _resolveDefaultValues() {
    for (var library in builders.values) {
      library.resolveDefaultValues();
    }
  }

  void _resolveMetadata() {
    for (var library in builders.values) {
      library.resolveMetadata();
    }
  }

  void _resolveTypes() {
    var nodesToBuildType = NodesToBuildType();
    for (var library in builders.values) {
      library.resolveTypes(nodesToBuildType);
    }
    VarianceBuilder(this).perform();
    computeSimplyBounded(this);
    TypeAliasSelfReferenceFinder().perform(this);
    TypesBuilder(this).build(nodesToBuildType);
  }

  void _setDefaultSupertypes() {
    for (var library in builders.values) {
      library.setDefaultSupertypes();
    }
  }

  void _writeLibraries({
    required OperationPerformanceImpl performance,
  }) {
    var bundleWriter = BundleWriter(
      elementFactory.dynamicRef,
    );

    for (var builder in builders.values) {
      bundleWriter.writeLibraryElement(builder.element);
    }

    var writeWriterResult = bundleWriter.finish();
    resolutionBytes = writeWriterResult.resolutionBytes;

    performance.getDataInt('length').add(resolutionBytes.length);
  }
}

class LinkResult {
  final Uint8List resolutionBytes;

  /// The results of applying macros in libraries.
  final List<MacroResultOutput> macroResults;

  LinkResult({
    required this.resolutionBytes,
    required this.macroResults,
  });
}

class MacroResultInput {
  final String code;

  MacroResultInput({
    required this.code,
  });
}

/// The results of applying macros in [library].
class MacroResultOutput {
  final LibraryFileKind library;
  final MacroProcessing processing;
  final String code;

  MacroResultOutput({
    required this.library,
    required this.processing,
    required this.code,
  });
}
