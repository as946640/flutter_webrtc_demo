import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc_deom/web_rtc/api.dart';
import 'package:get/get.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as flutter_webrtc;
import 'package:permission_handler/permission_handler.dart';

/// webRtc 拉流地址解析
class WebRTCUri {
  /// 服务器 地址
  late String api;

  /// 推流地址
  late String streamUrl;

  /// webrtc 地址解析
  static WebRTCUri parse(String url, {type = 'play'}) {
    Uri uri = Uri.parse(url);

    String schema = 'https'; // For native, default to HTTPS
    if (uri.queryParameters.containsKey('schema')) {
      schema = uri.queryParameters['schema']!;
    } else {
      schema = 'https';
    }

    var port = (uri.port > 0) ? uri.port : 443;
    if (schema == 'https') {
      port = (uri.port > 0) ? uri.port : 443;
    } else if (schema == 'http') {
      port = (uri.port > 0) ? uri.port : 1985;
    }

    String api = '/rtc/v1/play/';
     // 如果是推流的话
    if (type == 'publish') {
      api = '/rtc/v1/publish/';
    }
    if (uri.queryParameters.containsKey('play')) {
      api = uri.queryParameters['play']!;
    }

    var apiParams = [];
    for (var key in uri.queryParameters.keys) {
      if (key != 'api' && key != 'play' && key != 'schema') {
        apiParams.add('${key}=${uri.queryParameters[key]}');
      }
    }

    var apiUrl = '${schema}://${uri.host}:${port}${api}';
    if (!apiParams.isEmpty) {
      apiUrl += '?' + apiParams.join('&');
    }

    WebRTCUri r = WebRTCUri();
    r.api = apiUrl;
    r.streamUrl = url;
    print('Url ${url} parsed to api=${r.api}, stream=${r.streamUrl}');
    return r;
  }
}

/// 视频大小
class VideoSize {
  VideoSize(this.width, this.height);

  /// 格式化视频大小  1280x720 -> [1280,720]
  factory VideoSize.fromString(String size) {
    final parts = size.split('x');
    return VideoSize(int.parse(parts[0]), int.parse(parts[1]));
  }
  final int width;
  final int height;

  @override
  String toString() {
    return '$width x $height';
  }
}

/// webRtc 控制器
class WebRtcController extends GetxController {
  /// 视频输出设备id
  String? selectedVideoInputId;

  MediaStream? _localStream;

  /// 空的话会走摄像头的分辨率
  VideoSize? videoSize;

  /// 用户自身推流状态 0 未开始  1 成功 2 失败
  final isConnectState = 0.obs;

  Map<String, dynamic> mediaConstraints = {
    'audio': {
      "echoCancellation": true,
      "autoGainControl": true,
      "noiseSuppression": true
    },
    'video': {
      'facingMode': 'user', // 使用前置摄像头
      'mirror': true, // 设置镜像效果 目前测试没有效果
    },
  };

  List<RTCRtpSender> senders = <RTCRtpSender>[];

  /// rtc 视频流数组
  final rtcList = [].obs;

  /// 设备信息
  List devices = [];

  /// 添加远程视频
  addRemoteLive(String url, {Function(bool)? callback}) async {
    try {
      int renderId = DateTime.now().millisecondsSinceEpoch;
      RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
      await remoteRenderer.initialize();

      // 设置本地描述
      var pc2 = await createPeerConnection({'sdpSemantics': "unified-plan"});
      var offer = await pc2.createOffer({
        'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
      });
      await pc2.setLocalDescription(offer);
      pc2.onTrack = (event) {
        if (event.track.kind == 'video') {
          pc2.addTrack(event.track, event.streams[0]);
          remoteRenderer.srcObject = event.streams[0];
        }
      };

      // 链接状态 和 ice链接状态 回调
      pc2.onConnectionState = (state) {
        onConnectionState(state, renderId);
      };
      pc2.onIceConnectionState = (state) {
        onIceConnectionState(state, renderId);
      };

      await pc2.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      await pc2.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      // 获取拉流视频的远程 answer 描述
      var answer = await webRtcHandshake(url, offer.sdp ?? '');
      await pc2.setRemoteDescription(answer);

      Map webRtcData = {
        "renderId": renderId,
        "pc": pc2,
        "renderer": remoteRenderer,
        "slef": false,
      };

      rtcList.value = [
        ...rtcList,
        ...[webRtcData]
      ];

      callback?.call(true);
    } catch (e) {
      print('webrtc - 添加远程视频失败$e');
      callback?.call(false);
    }
  }

  /// 开启摄像头预览 一进来就要开始 因为主播自己的要放在第一位
  Future<void> openVideo() async {
    var locatPc = await createPeerConnection({
      'sdpSemantics': 'unified-plan',
    });
    int renderId = DateTime.now().millisecondsSinceEpoch;
    RTCVideoRenderer localRenderer = RTCVideoRenderer();
    localRenderer.initialize();

    // 获取本地视频流
    if (videoSize != null) {
      mediaConstraints['video']['width'] = videoSize?.width;
      mediaConstraints['video']['height'] = videoSize?.height;
    }
    _localStream = await flutter_webrtc.navigator.mediaDevices
        .getUserMedia(mediaConstraints);

    _localStream?.getTracks().forEach((MediaStreamTrack track) async {
      var rtpSender = await locatPc.addTrack(track, _localStream!);
      senders.add(rtpSender);
    });

    /// 视频帧处理
    // 添加视频帧处理器
    // var processor =
    //     flutter_webrtc.AudioOutputOptions(_localStream!.getVideoTracks()[0]);
    // processor.onFrame.listen((frame) {
    //   // 处理视频帧数据
    //   // 在这里可以对视频帧进行自定义处理
    // });

    // // 添加视频帧生成器
    // MediaStreamTrackGenerator generator = MediaStreamTrackGenerator();
    // generator.onFrameRequested.listen((_) {
    //   // 生成视频帧数据
    //   // 在这里可以自定义生成视频帧的逻辑，并通过generator.addFrame方法添加到视频流中
    // });

    // _localStream?.getTracks().forEach((MediaStreamTrack track) async {
    //   // 将处理器添加到视频轨道中
    //   track.addSink(processor);

    //   var rtpSender = await locatPc.addTrack(track, _localStream!);
    //   senders.add(rtpSender);
    // });

    localRenderer.srcObject = _localStream;

    Map webRtcData = {
      "renderId": renderId,
      "pc": locatPc,
      "renderer": localRenderer,
      "slef": true,
    };

    rtcList.value = [
      ...[webRtcData],
      ...rtcList,
    ];
  }

  /// 切换摄像头
  Future<void> selectVideoInput(String? deviceId) async {
    selectedVideoInputId = deviceId;

    mediaConstraints = {
      'audio': true,
      'video': {
        if (selectedVideoInputId != null && kIsWeb)
          'deviceId': selectedVideoInputId,
        if (selectedVideoInputId != null && !kIsWeb)
          'optional': [
            {'sourceId': selectedVideoInputId}
          ],
        'frameRate': 60,
      },
    };

    setMediaConstraints(deviceId, mediaConstraints);
  }

  /// 设置视频大小
  Future<void> setVideoSize(width, height) async {
    videoSize = VideoSize(width, height);
    mediaConstraints = {
      'audio': true,
      'video': {
        if (selectedVideoInputId != null && kIsWeb)
          'deviceId': selectedVideoInputId,
        if (selectedVideoInputId != null && !kIsWeb)
          'optional': [
            {'sourceId': selectedVideoInputId}
          ],
        'width': videoSize?.width,
        'height': videoSize?.height,
        'frameRate': 60,
      },
    };

    setMediaConstraints(selectedVideoInputId, mediaConstraints);
  }

  /// 切换推流视频配置
  Future<void> setMediaConstraints(String? deviceId, mediaConstraints) async {
    selectedVideoInputId = deviceId;

    var localRenderer = rtcList[0]['renderer'];
    localRenderer.srcObject = null;

    _localStream?.getTracks().forEach((track) async {
      await track.stop();
    });

    var newLocalStream = await flutter_webrtc.navigator.mediaDevices
        .getUserMedia(mediaConstraints);
    _localStream = newLocalStream;
    localRenderer.srcObject = _localStream;

    var newTrack = _localStream?.getVideoTracks().first;
    var sender =
        senders.firstWhereOrNull((sender) => sender.track?.kind == 'video');
    var params = sender!.parameters;
    params.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
    await sender.setParameters(params);
    await sender.replaceTrack(newTrack);
  }

  /// 建立本地视频推流
  Future<void> addLocalMedia(String url, {Function(bool)? callback}) async {
    try {
      var locatPc = rtcList[0]['pc'];
      var renderId = rtcList[0]['renderId'];

      locatPc.onConnectionState = (state) {
        onConnectionState(state, renderId);
      };
      locatPc.onIceConnectionState = (state) {
        onIceConnectionState(state, renderId);
      };
      locatPc.getStats().then(peerConnectionState);

      /// 进行 webrtc  握手
      var offer = await locatPc.createOffer();
      await locatPc.setLocalDescription(offer);
      var answer = await webRtcHandshake(url, offer.sdp ?? '', type: 'publish');
      // 设置 本地推流的 远程描述  为 远程的 answer
      await locatPc.setRemoteDescription(answer);
      callback?.call(true);
    } catch (e) {
      print('开启本地 推流出错$e');
      callback?.call(false);
    }
  }

  /// 关闭指定的推流
  Future<void> closeRenderId(int renderId) async {
    var _inx = rtcList.indexWhere((item) => item['renderId'] == renderId);

    if (_inx == -1) {
      print('直播不存在');
      return;
    }
    rtcList[_inx]['pc'].close();
    rtcList[_inx]['renderer'].srcObject = null;
    rtcList.removeAt(_inx);
  }

  /// 关闭全部推流
  Future<void> close() async {
    for (var i = 0; i < rtcList.length; i++) {
      rtcList[i]['pc'].close();
      rtcList[i]['renderer'].srcObject = null;
    }

    rtcList.clear();
    rtcList.value = [];
  }

  /// 获取设备列表信息
  Future<void> loadDevices() async {
    if (WebRTC.platformIsAndroid || WebRTC.platformIsIOS) {
      var status = await Permission.bluetooth.request();
      if (status.isPermanentlyDenied) {
        print('BLEpermdisabled');
      }

      status = await Permission.bluetoothConnect.request();
      if (status.isPermanentlyDenied) {
        print('ConnectPermdisabled');
      }
    }
    devices = await flutter_webrtc.navigator.mediaDevices.enumerateDevices();

    // 默认前置摄像头
    selectedVideoInputId = getVideoDevice();

    print(selectedVideoInputId);
  }

  /// webrtc 链接状态回调
  dynamic onConnectionState(RTCPeerConnectionState state, int index) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        print('$index  链接 成功');
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        print('$index  链接 失败');
        break;
      default:
        print('$index  链接 还未建立成功');
    }
  }

  /// webrtc ice 建立状态
  dynamic onIceConnectionState(RTCIceConnectionState state, int index) {
    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        print('$index ice对等 链接 失败');
        break;
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
        print('$index ice对等 链接 成功 开始推流');
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        print('$index ice对等 链接断开 可以尝试重新连接');
        break;
      default:
    }
  }

  /// 推流状态回调 获取一些 网络状态或者丢包率
  dynamic peerConnectionState(state) {
    print('当前推流状态  $state');
  }

  /// 获取前置或者后置摄像头
  String getVideoDevice({bool front = true}) {
    for (final device in devices) {
      if (device.kind == 'videoinput') {
        if (front && device.label.contains('front')) {
          return device.deviceId;
        } else if (!front && device.label.contains('back')) {
          return device.deviceId;
        }
      }
    }
    return "";
  }
}
