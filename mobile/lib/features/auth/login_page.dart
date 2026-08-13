import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/auth_api.dart';
import '../../config/app_config.dart';
import '../../services/auth_store.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _needsCredentials = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final config = ref.read(appConnectionConfigProvider);
    if (config.hasFixedServerUrl) {
      _serverController.text = config.normalizedFixedServerUrl()!;
      _needsCredentials = true;
    } else if (config.manualServerEntryEnabled) {
      _restoreServerAddress();
    }
  }

  Future<void> _restoreServerAddress() async {
    final value = await ref.read(authStoreProvider).readBaseUrl();
    if (mounted && value != null) {
      _serverController.text = value;
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);

    try {
      if (_needsCredentials) {
        await ref.read(authControllerProvider.notifier).login(
              baseUrl: _serverController.text,
              username: _usernameController.text,
              password: _passwordController.text,
            );
      } else {
        final status = await ref
            .read(authControllerProvider.notifier)
            .connectToServer(baseUrl: _serverController.text);
        if (mounted && status.enabled) {
          setState(() => _needsCredentials = true);
        }
      }
    } on AuthApiException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = '登录失败，请稍后重试');
      }
    }
  }

  Future<void> _changeServer() async {
    await ref.read(authControllerProvider.notifier).forgetServer();
    if (!mounted) return;
    setState(() {
      _needsCredentials = false;
      _usernameController.clear();
      _passwordController.clear();
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final loading = authState.isLoading;
    final colors = Theme.of(context).colorScheme;
    final config = ref.watch(appConnectionConfigProvider);

    if (!config.hasFixedServerUrl && !config.manualServerEntryEnabled) {
      return const _MissingServerConfigurationPage();
    }

    final showServerField = !config.hasFixedServerUrl && !_needsCredentials;
    final showChangeServer =
        !config.hasFixedServerUrl && config.manualServerEntryEnabled;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Icon(
                        Icons.school_outlined,
                        size: 56,
                        color: colors.primary,
                        semanticLabel: 'DeepTutor',
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _needsCredentials ? '登录 DeepTutor' : '连接 DeepTutor',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _needsCredentials
                            ? '使用你的 DeepTutor 账户继续学习。'
                            : '连接开发服务器，应用会自动检测是否需要登录。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 32),
                      if (showServerField)
                        TextFormField(
                          controller: _serverController,
                          enabled: !loading,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          enableSuggestions: false,
                          onFieldSubmitted: loading ? null : (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: '开发服务器地址',
                            hintText: 'http://10.0.2.2:8001',
                            helperText: '仅调试版本可配置',
                            prefixIcon: Icon(Icons.dns_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? '请输入服务器地址'
                                  : null,
                        ),
                      if (_needsCredentials) ...<Widget>[
                        TextFormField(
                          controller: _usernameController,
                          enabled: !loading,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          autofillHints: const <String>[
                            AutofillHints.username,
                          ],
                          decoration: const InputDecoration(
                            labelText: '用户名',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? '请输入用户名'
                                  : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          enabled: !loading,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const <String>[AutofillHints.password],
                          onFieldSubmitted: loading ? null : (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: '密码',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                              onPressed: loading
                                  ? null
                                  : () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.isEmpty ? '请输入密码' : null,
                        ),
                      ],
                      if (_errorMessage != null) ...<Widget>[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          label: '登录错误：$_errorMessage',
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: colors.onErrorContainer,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: loading ? null : _submit,
                          child: loading
                              ? Semantics(
                                  label: '正在登录',
                                  liveRegion: true,
                                  child: const SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                )
                              : Text(_needsCredentials ? '登录' : '连接'),
                        ),
                      ),
                      if (_needsCredentials && showChangeServer) ...<Widget>[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: loading ? null : _changeServer,
                          child: const Text('更换开发服务器'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MissingServerConfigurationPage extends StatelessWidget {
  const _MissingServerConfigurationPage();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.settings_ethernet_outlined,
                    size: 56,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'DeepTutor 尚未配置',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '当前版本没有配置服务地址，请联系应用管理员。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
