import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as flutterWebRtc;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_webrtc_deom/web_rtc/rtc_util.dart';
import 'package:get/get.dart';

class WebRtcWidget extends StatefulWidget {
  const WebRtcWidget({super.key});

  @override
  State<WebRtcWidget> createState() => _WebRtcWidgetState();
}

class _WebRtcWidgetState extends State<WebRtcWidget> {
  WebRtcController webRtcController = Get.put(WebRtcController());

  String webRtcUrl = '';

  /// 本机设备列表
  List<MediaDeviceInfo> _devices = [];

  bool isConnect = false;

  bool fornt = true;

  openVideo() {
    webRtcController.openVideo();
  }

  /// 添加远程
  addRemoteWebRtc() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return BotInput(
          send: (String value) {
            if (value.isEmpty) {
              return;
            }
            webRtcController.addRemoteLive(
              value,
              callback: (res) {
                if (res) {
                  setState(() {});
                } else {
                  print('添加远程出错');
                }
              },
            );
          },
        );
      },
    );
  }

  /// 开启本地
  openRtc() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return BotInput(
          send: (String value) {
            if (value.isEmpty) {
              return;
            }
            webRtcController.addLocalMedia(
              value,
              callback: (bool res) {
                if (res) {
                  setState(() {});
                } else {
                  print('开启本地出错');
                }
              },
            );
          },
        );
      },
    );
  }

  switchVideoInput() async {
    String deviceId = webRtcController.getVideoDevice(front: !fornt);
    await webRtcController.selectVideoInput(deviceId);
    fornt = !fornt;
  }

  switchRatio() {
    webRtcController.setVideoSize(500, 500);
  }

  /// 关闭推流
  closeLocal() async {
    var rtc = webRtcController.rtcList[0];
    if (rtc['slef'] == false) {
      return;
    }

    await webRtcController.closeRenderId(rtc['renderId']);
    setState(() {});
  }

  /// 关闭所有
  Future<void> _stop() async {
    webRtcController.close();
  }

  @override
  void initState() {
    super.initState();
    webRtcController.loadDevices();
    flutterWebRtc.navigator.mediaDevices.ondevicechange = (event) {
      webRtcController.loadDevices();
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 400,
              color: Colors.black.withOpacity(0.4),
              child: Obx(
                () => GridView.builder(
                  itemCount: webRtcController.rtcList.value.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (contex, i) {
                    return Container(
                      width: 200,
                      height: 200,
                      color: Colors.red,
                      child: RTCVideoView(
                          webRtcController.rtcList[i]['renderer'],
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                    );
                  },
                ),
              ),
            ),
            Wrap(
              children: [
                TextButton(
                  onPressed: addRemoteWebRtc,
                  child: const Text("添加远程视频"),
                ),
                TextButton(
                  onPressed: openVideo,
                  child: const Text("开启摄像头预览"),
                ),
                TextButton(
                  onPressed: openRtc,
                  child: const Text("开始推流"),
                ),
                TextButton(
                  onPressed: closeLocal,
                  child: const Text("关闭推流"),
                ),
                TextButton(
                  onPressed: switchVideoInput,
                  child: const Text("切换摄像头"),
                ),
                TextButton(
                  onPressed: switchRatio,
                  child: const Text("切换分辨率 500 * 500"),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _stop();
        },
        tooltip: 'Hangup',
        child: const Icon(Icons.phone),
      ),
    );
  }

  Widget BotInput({required Function(String value) send}) {
    return TextField(
      autofocus: true,
      textInputAction: TextInputAction.send,
      textAlignVertical: TextAlignVertical.center, // 垂直居中对
      decoration: const InputDecoration(
        isCollapsed: true,
        hintText: '输入推拉流地址...',
        border: InputBorder.none,
        counterText: '',
      ),
      onSubmitted: (value) {
        Navigator.of(context).pop();
        send.call(value);
      },
    );
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
