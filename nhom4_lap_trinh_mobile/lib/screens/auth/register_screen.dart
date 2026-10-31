import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _orgController = TextEditingController();
  final _studentCodeController = TextEditingController();

  String _selectedRole = UserRole.student;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _orgController.dispose();
    _studentCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.register(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      role: _selectedRole,
      organization: _orgController.text.trim(),
      studentCode: _selectedRole == UserRole.student
          ? _studentCodeController.text.trim()
          : '',
    );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Đăng ký tài khoản thành công!'),
        ),
      );
      Navigator.pop(context);
    } else if (authProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(authProvider.errorMessage!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đăng Ký Tài Khoản'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Chọn Vai trò người dùng (SegmentedButton)
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chọn Vai Trò Trong Hệ Thống:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: UserRole.student,
                              label: Text('Sinh Viên',
                                  style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.school, size: 16),
                            ),
                            ButtonSegment(
                              value: UserRole.employer,
                              label: Text('Tuyển Dụng',
                                  style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.business, size: 16),
                            ),
                            ButtonSegment(
                              value: UserRole.staff,
                              label: Text('Cán Bộ',
                                  style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.verified_user, size: 16),
                            ),
                          ],
                          selected: {_selectedRole},
                          onSelectionChanged: (Set<String> newSelection) {
                            setState(() {
                              _selectedRole = newSelection.first;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getRoleDescription(_selectedRole),
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Họ và tên
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Họ và tên *',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Vui lòng nhập họ và tên';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Email
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email *',
                    hintText: 'vidu@edu.vn',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
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

                // Mật khẩu
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu *',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    border: const OutlineInputBorder(),
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
                const SizedBox(height: 12),

                // Xác nhận mật khẩu
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscurePassword,
                  decoration: const InputDecoration(
                    labelText: 'Xác nhận lại mật khẩu *',
                    prefixIcon: Icon(Icons.lock_reset_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val != _passwordController.text) {
                      return 'Mật khẩu xác nhận không khớp';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Thông tin đặc thù theo vai trò
                if (_selectedRole == UserRole.student) ...[
                  TextFormField(
                    controller: _studentCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Mã số sinh viên (MSSV) *',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (_selectedRole == UserRole.student &&
                          (val == null || val.trim().isEmpty)) {
                        return 'Vui lòng nhập mã sinh viên';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                TextFormField(
                  controller: _orgController,
                  decoration: InputDecoration(
                    labelText: _selectedRole == UserRole.employer
                        ? 'Tên Doanh nghiệp / Tổ chức tuyển dụng'
                        : 'Trường Đại học / Đơn vị đào tạo',
                    prefixIcon: const Icon(Icons.account_balance_outlined),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),

                // Nút Đăng ký
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed:
                        authProvider.isLoading ? null : _handleRegister,
                    child: authProvider.isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'HOÀN TẤT ĐĂNG KÝ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getRoleDescription(String role) {
    switch (role) {
      case UserRole.staff:
        return '🛡️ Cán bộ đào tạo: Có quyền chọn Ảnh/PDF ký số Blockchain và xuất mã QR văn bằng.';
      case UserRole.employer:
        return '🏢 Nhà tuyển dụng: Quét QR hồ sơ ứng viên và lưu kết quả thẩm định offline.';
      case UserRole.student:
      default:
        return '🎓 Sinh viên: Tra cứu bằng cấp, lưu trữ vào Sổ tay văn bằng và xuất trình offline.';
    }
  }
}
