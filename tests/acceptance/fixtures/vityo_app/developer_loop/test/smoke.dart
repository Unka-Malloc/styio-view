import '../lib/main.dart';

void main() {
  if (greeting != 'after') {
    throw StateError('saved edit was not observed by the test fixture');
  }
}
