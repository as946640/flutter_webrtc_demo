import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_webrtc_deom/web_rtc/rtc_util.dart';

/// webrtc 获取 远程 answer
Future webRtcHandshake(String url, String sdp, {type = 'play'}) async {
  Dio dio = Dio();
  WebRTCUri uri = WebRTCUri.parse(url.trim(), type: type);
  Map data = {
    'api': uri.api,
    'streamurl': uri.streamUrl,
    'sdp': sdp,
    'tid': "2b45a06"
  };

  try {
    dio.options.headers['Content-Type'] = 'application/json';
    dio.options.headers['Connection'] = 'close';
    dio.options.responseType = ResponseType.plain;

    Response response =
        await dio.post(uri.api, data: utf8.encode(json.encode(data)));

    if (response.statusCode == 200) {
      Map<String, dynamic> o = json.decode(response.data);
      if (!o.containsKey('code') || !o.containsKey('sdp') || o['code'] != 0) {
        if (o['code'] == 400) {
          // ToastUtils.showToast("错误 当前已有人在推流");
        }
        return Future.error(response.data);
      }
      return Future.value(RTCSessionDescription(o['sdp'], 'answer'));
    } else {
      // ToastUtils.showToast("直播服务认证失败", type: 'error');
      return Future.error('请求推流服务器信令验证失败 status: ${response.statusCode}');
    }
  } catch (err) {
    // ToastUtils.showToast("直播服务认证失败$err", type: 'error');
    print('获取 webrtc sdp 报错$err');
    throw Error();
  }
}
