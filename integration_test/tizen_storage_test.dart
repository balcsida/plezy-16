import 'dart:io';

import 'package:drift_sqflite/drift_sqflite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/services/credential_vault.dart';
import 'package:plezy/utils/platform_detector.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Tizen native preferences, vault and Drift survive reopen', (tester) async {
    expect(PlatformDetector.isTizen(), isTrue);
    final support = await getApplicationSupportDirectory();
    final directory = await Directory(support.path).createTemp('plezy-storage-probe-');
    final file = p.join(directory.path, 'probe.db');
    final preferenceKey = p.basename(directory.path);
    final prefs = SharedPreferencesAsync();
    AppDatabase? db;
    try {
      await prefs.setString(preferenceKey, 'fixture');
      expect(await SharedPreferencesAsync().getString(preferenceKey), 'fixture');
      final protected = await CredentialVault.protect('synthetic-tizen-token');
      expect(CredentialVault.isProtected(protected), isTrue);
      expect(protected, isNot(contains('synthetic-tizen-token')));
      db = AppDatabase.forTesting(SqfliteQueryExecutor(path: file, singleInstance: false));
      await db.customStatement('CREATE TABLE tizen_probe (value TEXT NOT NULL)');
      await db.transaction(() => db!.customStatement('INSERT INTO tizen_probe VALUES (?)', [protected]));
      final version = db.schemaVersion;
      await db.close();
      db = AppDatabase.forTesting(SqfliteQueryExecutor(path: file, singleInstance: false));
      final row = await db.customSelect('SELECT value FROM tizen_probe').getSingle();
      CredentialVault.invalidateCache();
      expect(await CredentialVault.reveal(row.read<String>('value')), 'synthetic-tizen-token');
      final schema = await db.customSelect('PRAGMA user_version').getSingle();
      expect(schema.read<int>('user_version'), version);
    } finally {
      await db?.close();
      await prefs.remove(preferenceKey);
      // Delete only the unique fixture directory created by this test.
      await directory.delete(recursive: true);
    }
  });
}
