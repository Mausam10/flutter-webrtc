import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as web_ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:dart_webrtc/dart_webrtc.dart';
import 'package:web/web.dart' as web;

const Map<int, String> _kErrorValueToErrorName = {
  1: 'MEDIA_ERR_ABORTED',
  2: 'MEDIA_ERR_NETWORK',
  3: 'MEDIA_ERR_DECODE',
  4: 'MEDIA_ERR_SRC_NOT_SUPPORTED',
};

const Map<int, String> _kErrorValueToErrorDescription = {
  1: 'The user canceled the fetching of the video.',
  2: 'A network error occurred while fetching the video.',
  3: 'An error occurred while trying to decode the video.',
  4: 'The video format is not supported.',
};

const String _kDefaultErrorMessage =
    'No further diagnostic information is available.';

class RTCVideoRenderer extends ValueNotifier<RTCVideoValue>
    implements VideoRenderer {
  RTCVideoRenderer()
      : _textureId = _textureCounter++,
        super(RTCVideoValue.empty);

  static const _elementIdForAudioManager = 'html_webrtc_audio_manager_list';

  web.HTMLAudioElement? _audioElement;
  static int _textureCounter = 1;

  web.MediaStream? _videoStream;
  web.MediaStream? _audioStream;
  MediaStreamWeb? _srcObject;

  final int _textureId;

  bool mirror = false;
  final _subscriptions = <StreamSubscription>[];

  String _objectFit = 'contain';
  bool _muted = false;

  set objectFit(String fit) {
    if (_objectFit == fit) return;
    _objectFit = fit;
    findHtmlView()?.style.objectFit = fit;
  }

  @override
  int get videoWidth => value.width.toInt();
  @override
  int get videoHeight => value.height.toInt();
  @override
  int get textureId => _textureId;
  @override
  bool get muted => _muted;
  @override
  set muted(bool mute) => _audioElement?.muted = _muted = mute;
  @override
  bool get renderVideo => _srcObject != null;

  String get _elementIdForAudio => 'audio_$viewType';
  String get _elementIdForVideo => 'video_$viewType';
  String get viewType => 'RTCVideoRenderer-$_textureId';

  void _updateAllValues(web.HTMLVideoElement fallback) {
    final element = findHtmlView() ?? fallback;
    value = value.copyWith(
      rotation: 0,
      width: element.videoWidth.toDouble(),
      height: element.videoHeight.toDouble(),
      renderVideo: renderVideo,
    );
  }

  @override
  MediaStream? get srcObject => _srcObject;

  @override
  set srcObject(MediaStream? stream) {
    if (stream == null) {
      findHtmlView()?.srcObject = null;
      _audioElement?.srcObject = null;
      _srcObject = null;
      return;
    }

    _srcObject = stream as MediaStreamWeb;

    if (_srcObject != null) {
      if (stream.getVideoTracks().isNotEmpty) {
        _videoStream = web.MediaStream();
        for (final track in _srcObject!.jsStream.getVideoTracks().toDart) {
          _videoStream!.addTrack(track);
        }
      }
      if (stream.getAudioTracks().isNotEmpty) {
        _audioStream = web.MediaStream();
        for (final track in _srcObject!.jsStream.getAudioTracks().toDart) {
          _audioStream!.addTrack(track);
        }
      }
    } else {
      _videoStream = null;
      _audioStream = null;
    }

    if (_audioStream != null) {
      _audioElement ??= web.HTMLAudioElement()
        ..id = _elementIdForAudio
        ..muted = stream.ownerTag == 'local'
        ..autoplay = true;
      _ensureAudioManagerDiv().append(_audioElement!);
      _audioElement?.srcObject = _audioStream;
    }

    final videoElement = findHtmlView();
    if (videoElement != null) {
      videoElement.srcObject = _videoStream;
      _applyDefaultVideoStyles(videoElement);
    }

    value = value.copyWith(renderVideo: renderVideo);
  }

  Future<void> setSrcObject({MediaStream? stream, String? trackId}) async {
    if (stream == null) {
      findHtmlView()?.srcObject = null;
      _audioElement?.srcObject = null;
      _srcObject = null;
      return;
    }

    _srcObject = stream as MediaStreamWeb;

    if (_srcObject != null) {
      if (stream.getVideoTracks().isNotEmpty) {
        _videoStream = web.MediaStream();
        for (final track in _srcObject!.jsStream.getVideoTracks().toDart) {
          if (track.id == trackId) {
            _videoStream!.addTrack(track);
          }
        }
      }
      if (stream.getAudioTracks().isNotEmpty) {
        _audioStream = web.MediaStream();
        for (final track in _srcObject!.jsStream.getAudioTracks().toDart) {
          _audioStream!.addTrack(track);
        }
      }
    } else {
      _videoStream = null;
      _audioStream = null;
    }

    if (_audioStream != null) {
      _audioElement ??= web.HTMLAudioElement()
        ..id = _elementIdForAudio
        ..muted = stream.ownerTag == 'local'
        ..autoplay = true;
      _ensureAudioManagerDiv().append(_audioElement!);
      _audioElement?.srcObject = _audioStream;
    }

    final videoElement = findHtmlView();
    if (videoElement != null) {
      videoElement.srcObject = _videoStream;
      _applyDefaultVideoStyles(videoElement);
    }

    value = value.copyWith(renderVideo: renderVideo);
  }

  web.HTMLDivElement _ensureAudioManagerDiv() {
    final div = web.document.getElementById(_elementIdForAudioManager);
    if (div != null) return div as web.HTMLDivElement;

    final newDiv = web.HTMLDivElement()
      ..id = _elementIdForAudioManager
      ..style.display = 'none';
    web.document.body?.append(newDiv);
    return newDiv;
  }

  web.HTMLVideoElement? findHtmlView() {
    final element = web.document.getElementById(_elementIdForVideo);
    return element is web.HTMLVideoElement ? element : null;
  }

  @override
  Future<void> dispose() async {
    _srcObject = null;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    final element = findHtmlView();
    element?.removeAttribute('src');
    element?.load();
    _audioElement?.remove();
    final audioManager = web.document.getElementById(_elementIdForAudioManager)
        as web.HTMLDivElement?;
    if (audioManager != null && !audioManager.hasChildNodes()) {
      audioManager.remove();
    }
    return super.dispose();
  }

  @override
  Future<bool> audioOutput(String deviceId) async {
    try {
      final element = _audioElement;
      if (element != null) {
        await element.setSinkId(deviceId).toDart;
        return true;
      }
    } catch (e) {
      print('Unable to setSinkId: $e');
    }
    return false;
  }

  @override
  Future<void> initialize() async {
    web_ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      for (final s in _subscriptions) {
        s.cancel();
      }
      _subscriptions.clear();

      final element = web.HTMLVideoElement()
        ..autoplay = true
        ..muted = true
        ..controls = false
        ..srcObject = _videoStream
        ..id = _elementIdForVideo
        ..setAttribute('playsinline', 'true');

      _applyDefaultVideoStyles(element);

      _subscriptions.add(element.onCanPlay.listen((_) {
        _updateAllValues(element);
      }));

      _subscriptions.add(element.onResize.listen((_) {
        _updateAllValues(element);
        onResize?.call();
      }));

      _subscriptions.add(element.onError.listen((_) {
        final error = element.error;
        throw PlatformException(
          code: _kErrorValueToErrorName[error!.code]!,
          message:
              error.message.isNotEmpty ? error.message : _kDefaultErrorMessage,
          details: _kErrorValueToErrorDescription[error.code],
        );
      }));

      _subscriptions.add(element.onEnded.listen((_) {}));

      return element;
    });
  }

  void _applyDefaultVideoStyles(web.HTMLVideoElement element) {
    if (mirror) {
      element.style.transform = 'scaleX(-1)';
    }
    element
      ..style.objectFit = _objectFit
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';
  }

  @override
  Function? onResize;

  @override
  Function? onFirstFrameRendered;
}
