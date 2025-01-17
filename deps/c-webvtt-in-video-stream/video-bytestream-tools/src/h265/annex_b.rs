use crate::{
    h265::{H265ByteStreamWrite, H265NalHeader},
    h26x::{
        annex_b::{
            AnnexBNalUnitWriter as AnnexBNalUnitWriterImpl,
            AnnexBRbspWriter as AnnexBRbspWriterImpl, AnnexBWriter as AnnexBWriterImpl,
        },
        NalUnitWrite, RbspWrite, Result,
    },
    webvtt::{WebvttTrack, WebvttWrite},
};
use std::{io::Write, time::Duration};

pub struct AnnexBWriter<W: ?Sized + Write>(AnnexBWriterImpl<W>);

impl<W: Write> AnnexBWriter<W> {
    pub fn new(inner: W) -> Self {
        Self(AnnexBWriterImpl::new(inner))
    }
}

impl<W: Write> H265ByteStreamWrite<W> for AnnexBWriter<W> {
    type Writer = AnnexBNalUnitWriter<W>;

    fn start_write_nal_unit(self) -> Result<AnnexBNalUnitWriter<W>> {
        self.0.start_write_nal_unit().map(AnnexBNalUnitWriter)
    }
}

pub struct AnnexBNalUnitWriter<W: ?Sized + Write>(AnnexBNalUnitWriterImpl<W>);

impl<W: Write> NalUnitWrite<W> for AnnexBNalUnitWriter<W> {
    type Writer = AnnexBRbspWriter<W>;
    type NalHeader = H265NalHeader;

    fn write_nal_header(self, nal_header: Self::NalHeader) -> Result<AnnexBRbspWriter<W>> {
        self.0.write_nal_header(nal_header).map(AnnexBRbspWriter)
    }
}

pub struct AnnexBRbspWriter<W: ?Sized + Write>(AnnexBRbspWriterImpl<W>);

impl<W: Write> RbspWrite<W> for AnnexBRbspWriter<W> {
    type Writer = AnnexBWriter<W>;

    fn finish_rbsp(self) -> Result<Self::Writer> {
        self.0.finish_rbsp().map(AnnexBWriter)
    }
}

impl<W: Write + ?Sized> WebvttWrite for AnnexBRbspWriter<W> {
    fn write_webvtt_header(
        &mut self,
        max_latency_to_video: Duration,
        send_frequency_hz: u8,
        subtitle_tracks: &[WebvttTrack],
    ) -> std::io::Result<()> {
        self.0
            .write_webvtt_header(max_latency_to_video, send_frequency_hz, subtitle_tracks)
    }

    fn write_webvtt_payload(
        &mut self,
        track_index: u8,
        chunk_number: u64,
        chunk_version: u8,
        video_offset: Duration,
        webvtt_payload: &str, // TODO: replace with string type that checks for interior NULs
    ) -> std::io::Result<()> {
        self.0.write_webvtt_payload(
            track_index,
            chunk_number,
            chunk_version,
            video_offset,
            webvtt_payload,
        )
    }
}
