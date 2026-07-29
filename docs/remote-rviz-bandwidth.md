# 원격 RViz 대역폭 진단 (blueboat → 노트북)

**날짜**: 2026-07-29
**증상**: blueboat에서 fast_lio mapping을 launch하고 노트북 RViz(`fast_lio/rviz/fastlio.rviz`)로
`/slam/fast_lio/points_body`를 볼 때 포인트가 나왔다 안 나왔다 함.
**결론**: 하드웨어 한계가 아니다. 노트북의 **온보드 기가비트 포트가 놀고 있고**, 대신 물려 있는
USB 이더넷 동글이 100Mbps로 협상되어 병목이 된 것.

일반적인 진단 절차는 [troubleshooting.md](troubleshooting.md#원격-rviz에서-포인트클라우드가-나왔다-안-나왔다-함)에
정리했습니다. 이 문서는 이 워크스페이스의 실측치와 구성을 남깁니다.

## 먼저 배제된 것들

| 후보 | 확인 결과 |
|:---|:---|
| QoS mismatch | pub/sub 양쪽 `BEST_EFFORT` + `VOLATILE`로 **일치**. 원인 아님 |
| TF 없음 / 프레임 불일치 | `odom` → `body` 조회 성공. RViz Fixed Frame(`odom`)도 유효 |
| RViz Decay Time | `points_body` 디스플레이는 Decay Time 1. 깜빡임의 원인이 아니라 결과를 보여줄 뿐 |
| 카메라 스트림이 대역폭 잠식 | `/image_raw/compressed`는 **subscriber 0** → DDS가 전송하지 않음 |
| DDS 디스커버리 실패 | publisher/subscriber 모두 정상 매칭. 디스커버리는 됨 |

디스커버리는 되는데 데이터만 안 오는 조합이 이 문제의 지문입니다. 작은 패킷(디스커버리)은
통과하고 큰 fragment(user data)만 유실되기 때문입니다.

## 측정치

```
노트북 유선 링크 속도                100 Mbps   (/sys/class/net/enx00e04c360017/speed)
유선 인터페이스 rx                   8.5 MB/s = 68 Mbps
ros2 topic bw (12초)                 메시지 0건
fragment 재조립 (5초 델타)           required 28,383 / ok 671  →  성공률 2.4%
로컬 유선 ping RTT                   123 ~ 151 ms   (정상은 1ms 미만)
```

바이트는 초당 8.5MB씩 도착하는데 메시지는 0건 — 즉 도착한 fragment가 재조립되지 못하고
버려지고 있습니다. RTT 143ms는 1Gbps LAN에서 나올 수 없는 값으로, 큐가 가득 찬
포화 상태(bufferbloat)를 독립적으로 뒷받침합니다.

## 링크 양단 구성 (병목이 어디인가)

이더넷은 양단 중 **느린 쪽**으로 협상됩니다. 그래서 어느 쪽이 100Mbps인지 확인해야 합니다.

| 위치 | 인터페이스 | 상태 |
|:---|:---|:---|
| blueboat | `eno1` (192.168.0.12) | **1000 Mbps 링크 성립** — 무죄 |
| 노트북 | `enx00e04c360017` (192.168.0.22) | USB 동글, `r8152` 드라이버, **USB 2.0 포트(480M)**, 100 Mbps 협상 |
| 노트북 | `enp0s31f6` (온보드) | Intel 550a (I219 계열, **기가비트**), `carrier=0` — **케이블 미연결** |

blueboat가 1000, 노트북이 100으로 서로 다르게 뜬다는 건 **둘이 직결이 아니라 중간에 스위치가
있다**는 뜻입니다. blueboat–스위치 구간은 기가비트고, 스위치–노트북 구간만 100Mbps입니다.

따라서 병목은 **노트북 쪽 USB 동글 구간 하나**입니다. 온보드 기가비트 포트에 케이블을 옮겨
꽂는 것만으로 이론상 10배가 확보됩니다.

## 왜 이만큼 무거운가

`points_body`는 `feats_undistort`(원본 전체)를 발행합니다:

```cpp
// fast_lio/src/slam/laserMapping.cpp:616
void publish_frame_body(...)
{
    int size = feats_undistort->points.size();   // dense_publish_en 적용 안 됨
```

주의할 점 두 가지:

1. `config/slam/mid360.yaml`의 `dense_publish_en`은 이 경로에 **적용되지 않습니다**
   (`publish_frame_world`에만 걸림). `points_body`에 실제로 걸리는 건 `point_filter_num`(현재 2)뿐입니다.
2. PCL `PointXYZINormal`은 포인트당 **48 바이트**입니다 — xyz+패딩 16, normal+패딩 16,
   intensity/curvature+패딩 16. XYZI만 필요한데 3배를 보내고 있는 셈입니다.

## 남은 확인 사항

**실제 메시지 크기와 발행 주기는 미측정입니다.** blueboat 로컬에서 `ros2 topic echo --field width`
/ `--field point_step`으로 재려다 중단했습니다. 노트북 쪽은 메시지가 도착하지 않아 측정이 불가능하니,
반드시 **blueboat에서** 실행해야 합니다:

```bash
ssh hero@192.168.0.12
source /opt/ros/humble/setup.bash && export ROS_DOMAIN_ID=123
ros2 topic echo /slam/fast_lio/points_body --once --field width       # 포인트 수
ros2 topic echo /slam/fast_lio/points_body --once --field point_step  # 48 확인
ros2 topic bw /slam/fast_lio/points_body                              # 실제 소요 대역폭
```

MID-360 10Hz + `point_filter_num=2` 기준 추정은 메시지당 약 500KB, 40Mbps 안팎이지만
실측 rx가 68Mbps로 더 높아 **추정과 실측이 어긋나 있습니다**. 케이블을 옮긴 뒤에도 증상이
남는다면 이 측정부터 하는 게 순서입니다.

## 부수 발견

`/slam/fast_lio/debug/map`(RViz의 `CloudMap` 디스플레이)은 **publisher가 0개**입니다.
네트워크와 무관하게 발행이 켜져 있지 않은 것이라, 링크를 고쳐도 이 디스플레이는 계속 비어 있습니다.

## 참고 수치

| 항목 | 노트북 | blueboat |
|:---|:---|:---|
| `net.core.rmem_max` | 268435456 (256MB) | 8388608 (8MB) |
| `net.core.wmem_max` | — | 8388608 (8MB) |

버퍼가 이번 문제의 주원인은 아닙니다(도착 자체가 안 되는 것이라). 다만 blueboat 쪽은 여유가
없는 편이라, 기가비트로 올린 뒤 대역폭이 커지면 그때 재검토할 값입니다.
