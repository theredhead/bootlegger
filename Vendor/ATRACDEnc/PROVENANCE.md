# ATRACDEnc

Source: https://github.com/dcherednik/atracdenc
Revision: cb170709f836cb43dc0312455188c791159d81dc
libgha submodule: 00a95243254cfb1e43b05888ebc68e9aa401507a
Retrieved: 2026-10-28

Source and notices are retained, with the decoder fix described below. Built from src/CMakeLists.txt
for the host Mac architecture, with a static, PCM-only libsndfile 1.2.2 dependency.
See LICENSE, per-file notices and the libgha notices. This optional offline encoder
is used only for capability-supported software ATRAC transfers. No Sony proprietary
codec or network encoding service is used.

Local decoder fix: PrepareAtrac1Decoder uses one 512-sample sound group per PCM
engine iteration instead of eight. The fixed 4096-sample loop could consume more
ATRAC groups than remained at EOF for group counts congruent to 6 or 7 modulo 8,
raising "Can't read AEA frame" on valid extracted recordings. Encoding is unchanged.
