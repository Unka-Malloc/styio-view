import 'resource_facts.dart';

abstract class ResourceProber {
  Future<ResourceFacts> probe();
}

class StaticResourceProber implements ResourceProber {
  const StaticResourceProber(this.facts);
  final ResourceFacts facts;
  @override
  Future<ResourceFacts> probe() async => facts;
}
