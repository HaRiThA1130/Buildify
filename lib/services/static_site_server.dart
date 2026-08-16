import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';

class StaticSiteServer {
  HttpServer? _server;
  final String localPath;
  final int port;
  final String publishDir; // relative path within localPath
  final void Function(String message, {bool isError})? onLog;

  StaticSiteServer({
    required this.localPath,
    required this.port,
    this.publishDir = '',
    this.onLog,
  });

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    onLog?.call('[server] listening on port $port serving $localPath');
    
    _server!.listen((HttpRequest request) {
      _handleRequest(request);
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  File? _findFile(String rootPath, String relativePath) {
    // 1. Direct match in rootDir
    final candidate = File(p.normalize(p.join(rootPath, relativePath)));
    if (candidate.existsSync()) return candidate;

    // 2. Check if files were extracted into a single subfolder
    final rootDir = Directory(rootPath);
    if (rootDir.existsSync()) {
      for (final entity in rootDir.listSync()) {
        if (entity is Directory) {
          final nested = File(p.normalize(p.join(entity.path, relativePath)));
          if (nested.existsSync()) return nested;
        }
      }
    }
    return null;
  }

  void _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'GET') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }

      String reqPath = request.uri.path;
      if (reqPath == '/' || reqPath.isEmpty) {
        reqPath = '/index.html';
      }

      final relPath = reqPath.startsWith('/') ? reqPath.substring(1) : reqPath;
      final rootDir = p.join(localPath, publishDir);

      File? targetFile = _findFile(rootDir, relPath);

      // Fallback for root index.html or SPA routing
      if (targetFile == null || !targetFile.existsSync()) {
        targetFile = _findFile(rootDir, 'index.html');
      }

      if (targetFile != null && await targetFile.exists()) {
        onLog?.call('[server] 200 GET $reqPath -> ${targetFile.path}');
        final mimeType = lookupMimeType(targetFile.path) ?? 'text/html';
        response.headers.contentType = ContentType.parse(mimeType);
        
        await targetFile.openRead().pipe(response);
      } else {
        onLog?.call('[server] 404 GET $reqPath (not found in $rootDir)', isError: true);
        response.statusCode = HttpStatus.notFound;
        response.headers.contentType = ContentType.html;
        response.write('<html><body><h1>404 Not Found</h1><p>No file matching <code>$reqPath</code> found in project directory.</p></body></html>');
        await response.close();
      }
    } catch (e) {
      onLog?.call('[server] Error handling request: $e', isError: true);
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.write('Internal Server Error: $e');
        await response.close();
      } catch (_) {}
    }
  }
}
