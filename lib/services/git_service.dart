import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive_io.dart';

class GitService {
  /// Clones a public GitHub repository by downloading and extracting its zip archive.
  /// Note: This is a simplified clone for Phase B.
  static Future<void> cloneRepository({
    required String repoUrl,
    required String localPath,
    void Function(String)? onProgress,
  }) async {
    try {
      final uri = Uri.parse(repoUrl);
      if (uri.host != 'github.com') {
        throw Exception('Only github.com URLs are supported currently.');
      }

      final segments = uri.pathSegments;
      if (segments.length < 2) {
        throw Exception('Invalid GitHub URL format.');
      }

      final owner = segments[0];
      final repo = segments[1].replaceAll('.git', '');

      onProgress?.call('Fetching repository info...');
      
      // Get default branch
      final apiUri = Uri.parse('https://api.github.com/repos/$owner/$repo');
      final apiRes = await http.get(apiUri);
      
      if (apiRes.statusCode != 200) {
        throw Exception('Failed to fetch repo info. Is it public?');
      }

      final repoData = jsonDecode(apiRes.body);
      final defaultBranch = repoData['default_branch'] ?? 'main';

      onProgress?.call('Downloading $defaultBranch branch...');

      // Download zip archive
      final zipUrl = 'https://github.com/$owner/$repo/archive/refs/heads/$defaultBranch.zip';
      final zipRes = await http.get(Uri.parse(zipUrl));

      if (zipRes.statusCode != 200) {
        throw Exception('Failed to download repository archive.');
      }

      onProgress?.call('Extracting files...');

      final bytes = zipRes.bodyBytes;
      final archive = ZipDecoder().decodeBytes(bytes);
      
      final rootDirName = '$repo-$defaultBranch/';

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          // Remove the root wrapper folder from the path
          final relativePath = filename.startsWith(rootDirName) 
              ? filename.substring(rootDirName.length) 
              : filename;
              
          if (relativePath.isEmpty) continue;

          final data = file.content as List<int>;
          final outFile = File('$localPath/$relativePath');
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        } else {
          // It's a directory
          final relativePath = filename.startsWith(rootDirName) 
              ? filename.substring(rootDirName.length) 
              : filename;
              
          if (relativePath.isNotEmpty) {
            await Directory('$localPath/$relativePath').create(recursive: true);
          }
        }
      }

      onProgress?.call('Clone complete.');
    } catch (e) {
      throw Exception('Git Clone Error: $e');
    }
  }
}
