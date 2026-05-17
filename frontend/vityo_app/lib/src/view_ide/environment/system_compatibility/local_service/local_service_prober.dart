import 'local_service_facts.dart';

abstract class LocalServiceProber {
  Future<LocalServiceFacts> probe();
}

class StaticLocalServiceProber implements LocalServiceProber {
  const StaticLocalServiceProber(this.facts);
  final LocalServiceFacts facts;
  @override
  Future<LocalServiceFacts> probe() async => facts;
}
