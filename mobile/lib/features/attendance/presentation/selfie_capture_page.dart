import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Full-screen selfie capture flow:
/// preview -> take -> preview/retake/use -> pop with photo bytes.
class SelfieCapturePage extends StatefulWidget {
  const SelfieCapturePage({super.key});

  @override
  State<SelfieCapturePage> createState() => _SelfieCapturePageState();
}

class _SelfieCapturePageState extends State<SelfieCapturePage> {
  CameraController? _controller;
  XFile? _captured;
  bool _initializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'Kamera tidak ditemukan.');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(camera, ResolutionPreset.high);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Tidak dapat mengakses kamera.';
          _initializing = false;
        });
      }
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final shot = await controller.takePicture();
      if (mounted) setState(() => _captured = shot);
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal mengambil foto.');
    }
  }

  Future<void> _usePhoto() async {
    final shot = _captured;
    if (shot == null || !mounted) return;
    try {
      final bytes = await shot.readAsBytes();
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal membaca foto.');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Foto Selfie'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tutup'),
              ),
            ],
          ),
        ),
      );
    }

    if (_captured != null) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: Image.file(File(_captured!.path), fit: BoxFit.contain),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  style:
                      OutlinedButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () => setState(() => _captured = null),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Ulangi'),
                ),
                FilledButton.icon(
                  onPressed: _usePhoto,
                  icon: const Icon(Icons.check),
                  label: const Text('Gunakan'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: Center(
            child: _controller != null && _controller!.value.isInitialized
                ? CameraPreview(_controller!)
                : const SizedBox(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white,
            child: IconButton(
              iconSize: 40,
              icon: const Icon(Icons.camera_alt, color: Colors.black),
              onPressed: _takePicture,
              tooltip: 'Ambil foto',
            ),
          ),
        ),
      ],
    );
  }
}
