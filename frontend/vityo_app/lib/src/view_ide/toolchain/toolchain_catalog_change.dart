import 'toolchain_catalog.dart';

abstract interface class ToolchainCatalogChange {
  ToolchainCatalog? get catalog;
  bool get deleted;
}
