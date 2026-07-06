import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../services/database_helper.dart';

enum BackendLogType { request, error, system }
enum HostingMode { persistent, ephemeral }

class BackendLogEvent {
  const BackendLogEvent({
    required this.id,
    required this.projectId,
    required this.sessionId,
    required this.message,
    required this.type,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String sessionId;
  final String message;
  final BackendLogType type;
  final DateTime createdAt;
}

class BackendProject {
  const BackendProject({
    required this.id,
    required this.name,
    required this.repoProvider,
    required this.url,
    required this.lastDeployedAt,
    required this.isLive,
    this.hostingMode = HostingMode.persistent,
    this.localPath = '',
  });

  final String id;
  final String name;
  final String repoProvider;
  final String url;
  final DateTime? lastDeployedAt;
  final bool isLive;
  final HostingMode hostingMode;
  final String localPath;

  BackendProject copyWith({
    String? name,
    String? repoProvider,
    String? url,
    DateTime? lastDeployedAt,
    bool? isLive,
    HostingMode? hostingMode,
    String? localPath,
  }) {
    return BackendProject(
      id: id,
      name: name ?? this.name,
      repoProvider: repoProvider ?? this.repoProvider,
      url: url ?? this.url,
      lastDeployedAt: lastDeployedAt ?? this.lastDeployedAt,
      isLive: isLive ?? this.isLive,
      hostingMode: hostingMode ?? this.hostingMode,
      localPath: localPath ?? this.localPath,
    );
  }
}

class BackendDeployment {
  const BackendDeployment({
    required this.id,
    required this.projectId,
    required this.framework,
    required this.sourceType,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String framework;
  final String sourceType;
  final DateTime createdAt;
}

class BackendSession {
  const BackendSession({
    required this.id,
    required this.projectId,
    required this.startedAt,
    required this.isRunning,
    required this.publicUrl,
    required this.tunnelProvider,
    required this.requestCount,
    required this.rps,
    required this.lowBattery,
  });

  final String id;
  final String projectId;
  final DateTime startedAt;
  final bool isRunning;
  final String publicUrl;
  final String tunnelProvider;
  final int requestCount;
  final double rps;
  final bool lowBattery;

  BackendSession copyWith({
    bool? isRunning,
    int? requestCount,
    double? rps,
    bool? lowBattery,
  }) {
    return BackendSession(
      id: id,
      projectId: projectId,
      startedAt: startedAt,
      isRunning: isRunning ?? this.isRunning,
      publicUrl: publicUrl,
      tunnelProvider: tunnelProvider,
      requestCount: requestCount ?? this.requestCount,
      rps: rps ?? this.rps,
      lowBattery: lowBattery ?? this.lowBattery,
    );
  }
}

class BackendState {
  const BackendState({
    required this.userName,
    required this.projects,
    required this.deployments,
    required this.activeSession,
    required this.logs,
    required this.hostMappings,
  });

  final String userName;
  final List<BackendProject> projects;
  final List<BackendDeployment> deployments;
  final BackendSession? activeSession;
  final List<BackendLogEvent> logs;
  final Map<String, String> hostMappings;

  BackendState copyWith({
    String? userName,
    List<BackendProject>? projects,
    List<BackendDeployment>? deployments,
    BackendSession? activeSession,
    List<BackendLogEvent>? logs,
    Map<String, String>? hostMappings,
  }) {
    return BackendState(
      userName: userName ?? this.userName,
      projects: projects ?? this.projects,
      deployments: deployments ?? this.deployments,
      activeSession: activeSession,
      logs: logs ?? this.logs,
      hostMappings: hostMappings ?? this.hostMappings,
    );
  }
}

class EmbeddedBackendService {
  EmbeddedBackendService()
    : _state = const BackendState(
        userName: 'user',
        projects: [],
        deployments: [],
        activeSession: null,
        logs: [],
        hostMappings: {},
      ) {
    unawaited(hydrateProjects());
  }

  final _uuid = const Uuid();
  final _rand = Random();
  final _stateController = StreamController<BackendState>.broadcast();
  final _projectLogControllers = <String, StreamController<BackendLogEvent>>{};
  final _sessionControllers = <String, StreamController<BackendSession>>{};
  Timer? _ticker;
  BackendState _state;

  BackendState get state => _state;
  Stream<BackendState> get stream => _stateController.stream;

  Future<void> hydrateProjects() async {
    try {
      final dbProjects = await DatabaseHelper.instance.getProjects();
      final loaded = dbProjects.map((row) {
        return BackendProject(
          id: row['id'] as String,
          name: row['name'] as String,
          repoProvider: row['type'] as String,
          url: row['source_uri'] as String,
          lastDeployedAt: DateTime.fromMillisecondsSinceEpoch(row['last_active_at'] as int),
          isLive: row['desired_state'] == 'running',
          hostingMode: row['hosting_mode'] == 'ephemeral'
              ? HostingMode.ephemeral
              : HostingMode.persistent,
          localPath: row['local_path'] as String,
        );
      }).toList();
      _emit(_state.copyWith(projects: loaded));
    } catch (_) {}
  }

  Future<void> devLogin({String userName = 'user'}) async {
    _emit(_state.copyWith(userName: userName));
  }

  Future<List<BackendProject>> listProjects() async => _state.projects;

  Future<BackendProject> createProject({
    required String name,
    required String sourceType,
    String? customUrl,
    HostingMode hostingMode = HostingMode.persistent,
    String? customLocalPath,
  }) async {
    final slug = name.toLowerCase().replaceAll(' ', '-');
    final id = _uuid.v4();

    String localPath = customLocalPath ?? '';
    if (localPath.isEmpty) {
      if (hostingMode == HostingMode.persistent) {
        final docDir = await getApplicationDocumentsDirectory();
        localPath = join(docDir.path, 'projects', id);
      } else {
        final tempDir = await getTemporaryDirectory();
        localPath = join(tempDir.path, 'ephemeral', id);
      }
    }
    try {
      final dir = Directory(localPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (_) {}

    final p = BackendProject(
      id: id,
      name: name,
      repoProvider: sourceType,
      url: customUrl ?? 'https://$slug.buildify.app',
      lastDeployedAt: DateTime.now(),
      isLive: false,
      hostingMode: hostingMode,
      localPath: localPath,
    );

    if (hostingMode == HostingMode.persistent) {
      try {
        await DatabaseHelper.instance.insertProject({
          'id': p.id,
          'name': p.name,
          'type': p.repoProvider,
          'hosting_mode': 'persistent',
          'source_uri': p.url,
          'local_path': p.localPath,
          'port': 3000,
          'subdomain': slug,
          'env_vars': '{}',
          'desired_state': 'stopped',
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'last_active_at': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {}
    }

    final host = Uri.tryParse(p.url)?.host;
    final hostMappings = Map<String, String>.from(_state.hostMappings);
    if (host != null && host.isNotEmpty) {
      hostMappings[host] = p.id;
    }
    _emit(
      _state.copyWith(
        projects: [..._state.projects, p],
        hostMappings: hostMappings,
      ),
    );
    return p;
  }

  String generateRandomSubdomain() {
    const adjectives = [
      'amazing',
      'golden',
      'swift',
      'brave',
      'silent',
      'lucky',
      'frozen',
      'bright',
      'rapid',
      'solar',
    ];
    const nouns = [
      'sunflower',
      'bridge',
      'harbor',
      'engine',
      'orbit',
      'river',
      'forest',
      'rocket',
      'signal',
      'anchor',
    ];
    final name =
        '${adjectives[_rand.nextInt(adjectives.length)]}-${nouns[_rand.nextInt(nouns.length)]}-${10 + _rand.nextInt(90)}';
    return name;
  }

  BackendProject? resolveHostname(String hostname) {
    final projectId = _state.hostMappings[hostname];
    if (projectId == null) return null;
    for (final project in _state.projects) {
      if (project.id == projectId) return project;
    }
    return null;
  }

  Future<BackendDeployment> createDeployment({
    required String projectId,
    required String framework,
    required String sourceType,
  }) async {
    final d = BackendDeployment(
      id: _uuid.v4(),
      projectId: projectId,
      framework: framework,
      sourceType: sourceType,
      createdAt: DateTime.now(),
    );
    _emit(_state.copyWith(deployments: [..._state.deployments, d]));
    _updateProject(projectId, (p) => p.copyWith(lastDeployedAt: d.createdAt));
    _log(
      projectId,
      _state.activeSession?.id ?? 'none',
      '-- deployment created --',
      BackendLogType.system,
    );
    return d;
  }

  Future<BackendSession> startSession({
    required String projectId,
    String? publicUrl,
    String tunnelProvider = 'cloudflare',
  }) async {
    _ticker?.cancel();
    final session = BackendSession(
      id: _uuid.v4(),
      projectId: projectId,
      startedAt: DateTime.now(),
      isRunning: true,
      publicUrl:
          publicUrl ?? _state.projects.firstWhere((p) => p.id == projectId).url,
      tunnelProvider: tunnelProvider,
      requestCount: 0,
      rps: 0,
      lowBattery: false,
    );
    _updateProject(projectId, (p) => p.copyWith(isLive: true));
    _emit(_state.copyWith(activeSession: session));
    _log(
      projectId,
      session.id,
      '-- server started on :8080 --',
      BackendLogType.system,
    );

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = _state.activeSession;
      if (current == null || !current.isRunning) return;
      final reqDelta = _rand.nextInt(4);
      final lowBattery = current.lowBattery || (_rand.nextInt(40) == 0);
      final next = current.copyWith(
        requestCount: current.requestCount + reqDelta,
        rps: reqDelta.toDouble(),
        lowBattery: lowBattery,
      );
      _emit(_state.copyWith(activeSession: next));

      if (reqDelta > 0) {
        _log(
          projectId,
          session.id,
          '[GET] /index.html 200 ${8 + _rand.nextInt(40)}ms',
          BackendLogType.request,
        );
      }
      if (_rand.nextInt(20) == 0) {
        _log(
          projectId,
          session.id,
          '[ERR] worker timeout on /api/status',
          BackendLogType.error,
        );
      }
      if (lowBattery && _rand.nextInt(8) == 0) {
        _log(
          projectId,
          session.id,
          '-- warning: battery below 20% while serving --',
          BackendLogType.system,
        );
      }
    });

    return session;
  }

  Future<void> stopSession({required String sessionId}) async {
    final current = _state.activeSession;
    if (current == null || current.id != sessionId) return;
    _ticker?.cancel();
    _log(
      current.projectId,
      sessionId,
      '-- server stopped --',
      BackendLogType.system,
    );
    _updateProject(current.projectId, (p) => p.copyWith(isLive: false));
    _emit(_state.copyWith(activeSession: null));

    final proj = _state.projects.where((p) => p.id == current.projectId).firstOrNull;
    if (proj != null && proj.hostingMode == HostingMode.ephemeral) {
      await deleteProject(proj.id);
    }
  }

  Future<void> deleteProject(String id) async {
    final proj = _state.projects.where((p) => p.id == id).firstOrNull;
    if (proj == null) return;

    if (proj.hostingMode == HostingMode.persistent) {
      try {
        await DatabaseHelper.instance.deleteProject(id);
      } catch (_) {}
    } else {
      try {
        final dir = Directory(proj.localPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
    }

    final next = _state.projects.where((p) => p.id != id).toList();
    _emit(_state.copyWith(projects: next));
  }

  Stream<BackendLogEvent> logsStream(String projectId) {
    return _projectLogControllers
        .putIfAbsent(
          projectId,
          () => StreamController<BackendLogEvent>.broadcast(),
        )
        .stream;
  }

  Stream<BackendSession> sessionStatusStream(String sessionId) {
    return _sessionControllers
        .putIfAbsent(
          sessionId,
          () => StreamController<BackendSession>.broadcast(),
        )
        .stream;
  }

  void dispose() {
    _ticker?.cancel();
    _stateController.close();
    for (final c in _projectLogControllers.values) {
      c.close();
    }
    for (final c in _sessionControllers.values) {
      c.close();
    }
  }

  void _emit(BackendState next) {
    _state = next;
    _stateController.add(_state);
    final session = _state.activeSession;
    if (session != null && _sessionControllers.containsKey(session.id)) {
      _sessionControllers[session.id]!.add(session);
    }
  }

  void _log(
    String projectId,
    String sessionId,
    String message,
    BackendLogType type,
  ) {
    final event = BackendLogEvent(
      id: _uuid.v4(),
      projectId: projectId,
      sessionId: sessionId,
      message: message,
      type: type,
      createdAt: DateTime.now(),
    );
    final logs = [..._state.logs, event];
    _emit(
      _state.copyWith(
        logs: logs.length > 300 ? logs.sublist(logs.length - 300) : logs,
      ),
    );
    if (_projectLogControllers.containsKey(projectId)) {
      _projectLogControllers[projectId]!.add(event);
    }
  }

  void _updateProject(
    String id,
    BackendProject Function(BackendProject) mapper,
  ) {
    final next =
        _state.projects.map((p) => p.id == id ? mapper(p) : p).toList();
    _emit(_state.copyWith(projects: next));
  }
}
