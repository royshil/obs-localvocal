use crate::{
    h26x::{NalUnitWriter, RbspWriter, Result},
    webvtt::{WebvttTrack, WebvttWrite},
};
use byteorder::WriteBytesExt;
use std::{io::Write, time::Duration};

pub(crate) struct AnnexBWriter<W: ?Sized + Write> {
    leading_zero_8bits_written: bool,
    inner: W,
}

impl<W: Write> AnnexBWriter<W> {
    pub fn new(inner: W) -> Self {
        Self {
            leading_zero_8bits_written: false,
            inner,
        }
    }

    pub fn start_write_nal_unit(mut self) -> Result<AnnexBNalUnitWriter<W>> {
        if !self.leading_zero_8bits_written {
            self.inner.write_u8(0)?;
            self.leading_zero_8bits_written = true;
        }
        self.inner.write_all(&[0, 0, 1])?;
        Ok(AnnexBNalUnitWriter {
            inner: NalUnitWriter::new(self.inner),
        })
    }
}

pub(crate) trait WriteNalHeader<W: ?Sized + Write> {
    fn write_to(self, writer: &mut W) -> Result<()>;
}

pub(crate) struct AnnexBNalUnitWriter<W: ?Sized + Write> {
    inner: NalUnitWriter<W>,
}

impl<W: Write> AnnexBNalUnitWriter<W> {
    pub fn write_nal_header(
        mut self,
        header: impl WriteNalHeader<W>,
    ) -> Result<AnnexBRbspWriter<W>> {
        header.write_to(&mut self.inner.inner)?;
        Ok(AnnexBRbspWriter {
            inner: RbspWriter::new(self.inner.inner),
        })
    }
}

pub(crate) struct AnnexBRbspWriter<W: ?Sized + Write> {
    inner: RbspWriter<W>,
}

impl<W: Write> AnnexBRbspWriter<W> {
    pub fn finish_rbsp(self) -> Result<AnnexBWriter<W>> {
        self.inner
            .finish_rbsp()
            .map(|writer| AnnexBWriter::new(writer))
    }
}

impl<W: Write + ?Sized> WebvttWrite for AnnexBRbspWriter<W> {
    fn write_webvtt_header(
        &mut self,
        max_latency_to_video: Duration,
        send_frequency_hz: u8,
        subtitle_tracks: &[WebvttTrack],
    ) -> std::io::Result<()> {
        self.inner
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
        self.inner.write_webvtt_payload(
            track_index,
            chunk_number,
            chunk_version,
            video_offset,
            webvtt_payload,
        )
    }
}
