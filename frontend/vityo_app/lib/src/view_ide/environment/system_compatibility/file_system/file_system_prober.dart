import 'file_system_facts.dart';

abstract class FileSystemProber {
  Future<FileSystemFacts> probe();
}

class StaticFileSystemProber implements FileSystemProber {
  const StaticFileSystemProber(this.facts);

  final FileSystemFacts facts;

  @override
  Future<FileSystemFacts> probe() async {
    return facts;
  }
}
