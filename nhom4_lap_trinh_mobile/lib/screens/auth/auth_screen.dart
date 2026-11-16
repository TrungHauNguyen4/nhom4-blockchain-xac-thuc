import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/spatial_card_deck.dart';
import '../../widgets/twinkling_dot_matrix_background.dart';
import 'register_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final GlobalKey<SpatialCardDeckState> _deckKey =
      GlobalKey<SpatialCardDeckState>();

  late final AnimationController _sheetController;
  static const SpringDescription _editorialSpring = SpringDescription(
    mass: 1.0,
    stiffness: 240.0,
    damping: 26.0,
  );

  bool _obscurePassword = true;
  bool _showLoginSheet = false;
  SpatialDeckMode _deckMode = SpatialDeckMode.cluster;

  @override
  void initState() {
    super.initState();
    _sheetController = AnimationController.unbounded(
      vsync: this,
      value: 0.0,
    );
  }

  @override
  void dispose() {
    _sheetController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _openLoginSheet() {
    if (_showLoginSheet) return;
    setState(() {
      _showLoginSheet = true;
      _deckMode = SpatialDeckMode.collapsed;
    });
    _deckKey.currentState?.setMode(SpatialDeckMode.collapsed);
    _sheetController.animateWith(
      SpringSimulation(
        _editorialSpring,
        _sheetController.value,
        1.0,
        0.0,
      ),
    );
  }

  void _closeLoginSheet() {
    if (!_showLoginSheet) return;
    setState(() {
      _showLoginSheet = false;
      _deckMode = SpatialDeckMode.cluster;
    });
    _deckKey.currentState?.setMode(SpatialDeckMode.cluster);
    _sheetController.animateWith(
      SpringSimulation(
        _editorialSpring,
        _sheetController.value,
        0.0,
        0.0,
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;
    if (!success && authProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(authProvider.errorMessage!),
        ),
      );
    }
  }

  Future<void> _handleGoogleLogin() async {
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.loginWithGoogle();

    if (!mounted) return;
    if (!success && authProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(authProvider.errorMessage!),
        ),
      );
    }
  }

  void _showForgotPasswordDialog() {
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_reset_rounded, color: Colors.blueAccent),
            SizedBox(width: 8),
            Expanded(child: Text('Đặt lại mật khẩu')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập địa chỉ email của bạn để nhận liên kết đặt lại mật khẩu từ Firebase:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Địa chỉ Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty) return;
              Navigator.pop(dialogCtx);
              final auth = context.read<AuthProvider>();
              final ok = await auth.resetPassword(email);
              if (!mounted) return;
              if (ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green.shade700,
                    content: Text(
                      'Đã gửi liên kết đặt lại mật khẩu đến $email! Vui lòng kiểm tra hộp thư đến (hoặc Thư rác/Spam).',
                    ),
                  ),
                );
              } else if (auth.errorMessage != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.red.shade700,
                    content: Text(auth.errorMessage!),
                  ),
                );
              }
            },
            child: const Text('Gửi liên kết'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    // Nếu có lỗi đăng xuất từ thiết bị khác -> tự động mở form để người dùng thấy rõ thông báo
    final hasError = authProvider.errorMessage != null &&
        authProvider.errorMessage!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF031226),
      body: Stack(
        children: [
          const Positioned.fill(
            child: TwinklingDotMatrixBackground(),
          ),
          // Lớp phủ vignette nhẹ giúp giữ độ tương phản cao cho chữ và form đăng nhập
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.05,
                    colors: [
                      const Color(0xFF031226).withValues(alpha: 0.12),
                      const Color(0xFF031226).withValues(alpha: 0.52),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return AnimatedBuilder(
              animation: _sheetController,
              builder: (context, _) {
                final double t = _sheetController.value.clamp(0.0, 1.0);
                final double deckHeight = (constraints.maxHeight *
                        (0.46 - 0.24 * t))
                    .clamp(130.0, 340.0);

                return SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 28,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Thanh Editorial Top Header & Bộ chuyển trạng thái Deck
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF18181A),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.asset(
                                          'assets/images/app_logo.png',
                                          width: 22,
                                          height: 22,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'BLOCKCHAIN • 2026',
                                        style: TextStyle(
                                          color: Color(0xFFECEBE6),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_showLoginSheet)
                                  TextButton.icon(
                                    onPressed: _closeLoginSheet,
                                    icon: const Icon(
                                      Icons.layers_outlined,
                                      size: 16,
                                      color: Color(0xFFECEBE6),
                                    ),
                                    label: const Text(
                                      'Khám phá thẻ',
                                      style: TextStyle(
                                        color: Color(0xFFECEBE6),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),

                        // 2. Interactive Spatial Card Deck (8 thẻ chuyển động tự động)
                        SizedBox(
                          height: deckHeight,
                          child: SpatialCardDeck(
                            key: _deckKey,
                            mode: _deckMode,
                            autoPlay: !_showLoginSheet,
                            onModeChanged: (newMode) {
                              if (mounted && _deckMode != newMode) {
                                setState(() => _deckMode = newMode);
                              }
                            },
                          ),
                        ),

                        // 3. Cảnh báo lỗi phiên đăng nhập (nếu có)
                        if (hasError)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade900.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: Colors.redAccent,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    authProvider.errorMessage!,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFFECEBE6),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Colors.redAccent,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: authProvider.clearError,
                                ),
                              ],
                            ),
                          ),

                        // 4. Phương án B: Intro CTA hoặc Login Sheet trượt lên bằng Spring Physics
                        if (!_showLoginSheet)
                          _buildEditorialIntroFooter()
                        else
                          Transform.translate(
                            offset: Offset(0, (1.0 - t) * 48),
                            child: Opacity(
                              opacity: t.clamp(0.0, 1.0),
                              child: _buildLoginFormCard(authProvider),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorialIntroFooter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'XÁC THỰC VĂN BẰNG',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: Color(0xFFECEBE6),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Blockchain Certificate & Degree Verifier',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFECEBE6),
              foregroundColor: const Color(0xFF141416),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: _openLoginSheet,
            child: const Text(
              'ĐĂNG NHẬP',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Chưa có tài khoản? ',
              style: TextStyle(color: Colors.white60),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RegisterScreen(),
                  ),
                );
              },
              child: const Text(
                'Đăng ký ngay',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFECEBE6),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoginFormCard(AuthProvider authProvider) {
    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF18181A),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Đăng Nhập Tài Khoản',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFFECEBE6),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Color(0xFFECEBE6)),
              decoration: InputDecoration(
                labelText: 'Email',
                hintText: 'vidu@edu.vn',
                labelStyle: const TextStyle(color: Colors.white70),
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon:
                    const Icon(Icons.email_outlined, color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF0E0E10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Vui lòng nhập email';
                }
                if (!val.contains('@')) {
                  return 'Định dạng email không hợp lệ';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(color: Color(0xFFECEBE6)),
              decoration: InputDecoration(
                labelText: 'Mật khẩu',
                labelStyle: const TextStyle(color: Colors.white70),
                prefixIcon:
                    const Icon(Icons.lock_outline, color: Colors.white70),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.white70,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                filled: true,
                fillColor: const Color(0xFF0E0E10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return 'Vui lòng nhập mật khẩu';
                }
                if (val.length < 6) {
                  return 'Mật khẩu tối thiểu 6 ký tự';
                }
                return null;
              },
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed:
                    authProvider.isLoading ? null : _showForgotPasswordDialog,
                child: const Text(
                  'Quên mật khẩu?',
                  style: TextStyle(
                    color: Color(0xFFECEBE6),
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF565C43),
                  foregroundColor: const Color(0xFFECEBE6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: authProvider.isLoading ? null : _handleLogin,
                child: authProvider.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFFECEBE6),
                        ),
                      )
                    : const Text(
                        'ĐĂNG NHẬP',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(child: Divider(color: Colors.white24)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'hoặc',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
                Expanded(child: Divider(color: Colors.white24)),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFECEBE6),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
              label: const Text(
                'Đăng nhập với Google',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onPressed: authProvider.isLoading ? null : _handleGoogleLogin,
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Chưa có tài khoản? ',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RegisterScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'Đăng ký ngay',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFECEBE6),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
