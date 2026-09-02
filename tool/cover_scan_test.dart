import 'package:kiko_local/src/services/local_library_scanner.dart';

Future<void> main() async {
  final scanner = LocalLibraryScanner();
  final works = await scanner.scanRoots(['/tmp/cover_test/扫描根']);
  for (final w in works) {
    print('作品: ${w.title}');
    print('  rj=${w.rjCode} cover=${w.coverPath} source=${w.coverSource}');
  }
}
