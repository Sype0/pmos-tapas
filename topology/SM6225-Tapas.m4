# AudioReach topology for the Xiaomi Redmi Note 12 4G (tapas, SM6225).
# Its ADSP runs the AudioReach (SPF) firmware, so the q6apm front ends and
# graphs come from this file: qcom/sm4250/SM6225-Tapas-tplg.bin, after the
# driver name (qcom,qrb4210-rb2-sndcard) and model of the sound card.
# Built with the m4 files of github.com/linux-msm/audioreach-topology; laid
# out like its QCM6490-IDP.m4 (WCD codec on the RX/TX codec DMA ports).
#
# hw:0,0 MultiMedia1 playback -> RX_CODEC_DMA_RX_0 (speaker, earpiece,
#                                headphones: WCD9370 behind the RX macro)
# hw:0,1 MultiMedia2 capture  <- TX_CODEC_DMA_TX_3 (WCD9370 analog mics)
# hw:0,2 MultiMedia3 capture  <- VA_CODEC_DMA_TX_0 (VA macro)
# SPDX-License-Identifier: BSD-3-Clause
include(`audioreach/audioreach.m4')
include(`audioreach/stream-subgraph.m4')
include(`audioreach/device-subgraph.m4')
include(`util/route.m4')
include(`util/mixer.m4')
include(`audioreach/tokens.m4')
dnl
dnl Playback MultiMedia1
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-vol-playback.m4, FRONTEND_DAI_MULTIMEDIA1,
	`S16_LE', 48000, 48000, 2, 2,
	0x00004001, 0x00004001, 0x00006001, `110000')
dnl
dnl Capture MultiMedia2
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-capture.m4, FRONTEND_DAI_MULTIMEDIA2,
	`S16_LE', 48000, 48000, 1, 2,
	0x00004002, 0x00004002, 0x00006020, `110000')
dnl
dnl Capture MultiMedia3
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-capture.m4, FRONTEND_DAI_MULTIMEDIA3,
	`S16_LE', 48000, 48000, 1, 2,
	0x00004003, 0x00004003, 0x00006040, `110000')
dnl
dnl DEVICE_SG_ADD(stream, stream-dai-id, stream-index,
dnl	format, min-rate, max-rate, min-channels, max-channels,
dnl	interface-type, interface-index, sd-line-idx, data-format,
dnl	sg-iid-start, cont-iid-start, mod-iid-start)
dnl
dnl WCD playback
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-playback.m4, `RX_CODEC_DMA_RX_0', RX_CODEC_DMA_RX_0,
	`S16_LE', 48000, 48000, 2, 2,
	LPAIF_INTF_TYPE_RXTX, CODEC_INTF_IDX_RX0, 0, DATA_FORMAT_FIXED_POINT,
	0x00004004, 0x00004004, 0x00006060)
dnl
dnl WCD capture
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-capture.m4, `TX_CODEC_DMA_TX_3', TX_CODEC_DMA_TX_3,
	`S16_LE', 48000, 48000, 1, 2,
	LPAIF_INTF_TYPE_RXTX, CODEC_INTF_IDX_TX3, 0, DATA_FORMAT_FIXED_POINT,
	0x00004005, 0x00004005, 0x00006080)
dnl
dnl VA capture
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-capture.m4, `VA_CODEC_DMA_TX_0', VA_CODEC_DMA_TX_0,
	`S16_LE', 48000, 48000, 1, 2,
	LPAIF_INTF_TYPE_VA, CODEC_INTF_IDX_TX0, 0, DATA_FORMAT_FIXED_POINT,
	0x00004006, 0x00004006, 0x000060a0)
dnl
STREAM_DEVICE_PLAYBACK_MIXER(RX_CODEC_DMA_RX_0, ``RX_CODEC_DMA_RX_0'', ``MultiMedia1'')
STREAM_DEVICE_PLAYBACK_ROUTE(RX_CODEC_DMA_RX_0, ``RX_CODEC_DMA_RX_0 Audio Mixer'', ``MultiMedia1, stream0.logger1'')
dnl
dnl STREAM_DEVICE_CAPTURE_MIXER(stream-index, kcontrol1, kcontrol2... kcontrolN)
STREAM_DEVICE_CAPTURE_MIXER(FRONTEND_DAI_MULTIMEDIA2, ``TX_CODEC_DMA_TX_3'')
STREAM_DEVICE_CAPTURE_MIXER(FRONTEND_DAI_MULTIMEDIA3, ``VA_CODEC_DMA_TX_0'')
dnl STREAM_DEVICE_CAPTURE_ROUTE(stream-index, mixer-name, route1, route2.. routeN)
STREAM_DEVICE_CAPTURE_ROUTE(FRONTEND_DAI_MULTIMEDIA2, ``MultiMedia2 Mixer'', ``TX_CODEC_DMA_TX_3, device120.logger1'')
STREAM_DEVICE_CAPTURE_ROUTE(FRONTEND_DAI_MULTIMEDIA3, ``MultiMedia3 Mixer'', ``VA_CODEC_DMA_TX_0, device110.logger1'')
