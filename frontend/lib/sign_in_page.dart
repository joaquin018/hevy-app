import 'package:flutter/material.dart';

import 'auth_controller.dart';

class SignInPage extends StatelessWidget {
  const SignInPage({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = AuthController.instance;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.fitness_center_rounded,
                    size: 64,
                    color: Color(0xFF7C8CFF),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'i7l',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 46, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Iniciar sesión',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 29, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Guarda tus rutinas, sesiones y récords en tu cuenta. Tu correo de Google será tu nombre de usuario.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF9399A6), height: 1.6),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: auth.busy ? null : auth.signIn,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: Text(
                      auth.busy
                          ? 'Esperando a Google…'
                          : 'Continuar con Google',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (auth.busy) ...[
                    const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Elige tu cuenta en el navegador y vuelve a la app.',
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: auth.cancelSignIn,
                      child: const Text('Cancelar'),
                    ),
                  ] else
                    const Text(
                      '¿Es tu primera vez? Tu cuenta se creará al continuar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF9399A6), fontSize: 12),
                    ),
                  if (auth.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        auth.error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFF9A9A)),
                      ),
                    ),
                  ...[
                    const SizedBox(height: 24),
                    Center(
                      child: TextButton(
                        key: const ValueKey('continuar-como-invitado'),
                        onPressed: auth.busy ? null : auth.continueAsGuest,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF9399A6),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        child: const Text('Continuar como invitado'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
