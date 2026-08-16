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
      
      for (final file in archive) {
        final filename = file.name;
        // GitHub zip archives always wrap all files in a single root folder (e.g. 'repo-branch/').
        // Strip the first folder segment to extract directly into localPath:
        final slashIndex = filename.indexOf('/');
        final relativePath = slashIndex != -1 
            ? filename.substring(slashIndex + 1) 
            : filename;
            
        if (relativePath.isEmpty) continue;

        final outPath = '$localPath/$relativePath';

        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(outPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }

      onProgress?.call('Clone complete.');
    } catch (e) {
      throw Exception('Git Clone Error: $e');
    }
  }
}
