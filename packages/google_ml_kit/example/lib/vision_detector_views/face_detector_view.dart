import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as imglib;
import 'package:path_provider/path_provider.dart';

import 'camera_view.dart';
import 'painters/face_detector_painter.dart';

class FaceDetectorView extends StatefulWidget {
  @override
  State<FaceDetectorView> createState() => _FaceDetectorViewState();
}

class _FaceDetectorViewState extends State<FaceDetectorView> {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
    ),
  );
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  String? _text;
  String? _tempFilePath;

  @override
  void dispose() {
    _canProcess = false;
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CameraView(
      title: 'Face Detector',
      customPaint: _customPaint,
      text: _text,
      onImage: (inputImage) {
        processImage(inputImage);
      },
      initialDirection: CameraLensDirection.front,
    );
  }

  Future<void> processImage(InputImage inputImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;
    setState(() {
      _text = '';
    });
    final faces = await _faceDetector.processImage(inputImage);
    if (inputImage.inputImageData?.size != null &&
        inputImage.inputImageData?.imageRotation != null) {
      final painter = FaceDetectorPainter(
          faces,
          inputImage.inputImageData!.size,
          inputImage.inputImageData!.imageRotation);
      _customPaint = CustomPaint(
          size: Size(inputImage.inputImageData!.size.width,
              inputImage.inputImageData!.size.height),
          painter: painter);

      String text = 'Faces found: ${faces.length}\n\n';

      for (final face in faces) {
        final Rect boundingBox = face.boundingBox;

        final double? rotX =
            face.headEulerAngleX; // Head is tilted up and down rotX degrees
        final double? rotY =
            face.headEulerAngleY; // Head is rotated to the right rotY degrees
        // final double? rotZ = face.headEulerAngleZ; // Head is tilted sideways rotZ degrees
        print('$boundingBox, $rotX, $rotY');
        if (rotX != null &&
            rotY != null &&
            rotX.abs() < 10.0 &&
            rotY.abs() > 20) {
          _canProcess = false;

          // save image
          print(inputImage.inputImageData!.inputImageFormat);

          final imglib.Image img = imglib.Image.fromBytes(
              inputImage.inputImageData!.size.width.toInt(),
              inputImage.inputImageData!.size.height.toInt(),
              inputImage.bytes!,
              format: imglib.Format.bgra);
          final imglib.PngEncoder pngEncoder = imglib.PngEncoder();
          final List<int> png = pngEncoder.encodeImage(img);

          final Directory tempDir = await getApplicationDocumentsDirectory();
          setState(() {
            final nowString = DateTime.now().toString();
            _tempFilePath = '${tempDir.path}/$nowString.png';
          });

          File(_tempFilePath!).writeAsBytes(png);

          //カメラのシャッターを切って、そのimageを別のviewへnavigateする
          Navigator.of(context)
              .push(MaterialPageRoute<bool>(builder: (BuildContext context) {
            return StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
              return Scaffold(
                appBar: AppBar(
                  title: Text('Captured Image'),
                ),
                body: WillPopScope(
                  onWillPop: () async {
                    Navigator.pop(context, true);
                    _canProcess = true;
                    await File(_tempFilePath!).delete();
                    return false;
                  },
                  child: Image.file(File(_tempFilePath!)),
                ),
              );
            });
          }));
          //_canProcess = false;
        }

        text += 'face: ${face.boundingBox}\n\n';
      }
      print(text);
    }
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }
}
