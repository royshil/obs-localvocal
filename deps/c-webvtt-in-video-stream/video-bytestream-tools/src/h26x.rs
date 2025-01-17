use byteorder::WriteBytesExt;
use std::{collections::VecDeque, io::Write, time::Duration};

use crate::webvtt::{write_webvtt_header, write_webvtt_payload, WebvttTrack, WebvttWrite};

pub(crate) mod annex_b;

pub(crate) type Result<T, E = std::io::Error> = std::result::Result<T, E>;

pub(crate) struct NalUnitWriter<W: ?Sized + Write> {
    pub(crate) inner: W,
}

pub trait NalUnitWrite<W: ?Sized + Write> {
    type Writer: RbspWrite<W>;
    type NalHeader;
    fn write_nal_header(self, nal_header: Self::NalHeader) -> Result<Self::Writer>;
}

impl<W: Write> NalUnitWriter<W> {
    pub(crate) fn new(inner: W) -> Self {
        Self { inner }
    }
}

pub(crate) struct RbspWriter<W: ?Sized + Write> {
    last_written: VecDeque<u8>,
    inner: W,
}

pub trait RbspWrite<W: ?Sized + Write> {
    type Writer;
    fn finish_rbsp(self) -> Result<Self::Writer>;
}

impl<W: Write> RbspWriter<W> {
    pub fn new(inner: W) -> Self {
        Self {
            last_written: VecDeque::with_capacity(3),
            inner,
        }
    }

    pub fn finish_rbsp(mut self) -> Result<W> {
        self.write_u8(0x80)?;
        Ok(self.inner)
    }
}

impl<W: ?Sized + Write> Write for RbspWriter<W> {
    fn write(&mut self, buf: &[u8]) -> Result<usize> {
        let mut written = 0;
        for &byte in buf {
            let mut last_written_iter = self.last_written.iter();
            if last_written_iter.next() == Some(&0)
                && last_written_iter.next() == Some(&0)
                && (byte == 0 || byte == 1 || byte == 2 || byte == 3)
            {
                self.inner.write_u8(3)?;
                self.last_written.clear();
            }
            self.inner.write_u8(byte)?;
            written += 1;
            self.last_written.push_back(byte);
            if self.last_written.len() > 2 {
                self.last_written.pop_front();
            }
        }
        Ok(written)
    }

    fn flush(&mut self) -> Result<()> {
        self.inner.flush()
    }
}

pub(crate) fn write_sei_header<W: ?Sized + Write>(
    writer: &mut W,
    mut payload_type: usize,
    mut payload_size: usize,
) -> std::io::Result<()> {
    while payload_type >= 255 {
        writer.write_u8(255)?;
        payload_type -= 255;
    }
    writer.write_u8(payload_type.try_into().unwrap())?;
    while payload_size >= 255 {
        writer.write_u8(255)?;
        payload_size -= 255;
    }
    writer.write_u8(payload_size.try_into().unwrap())?;
    Ok(())
}

impl<W: Write + ?Sized> WebvttWrite for RbspWriter<W> {
    fn write_webvtt_header(
        &mut self,
        max_latency_to_video: Duration,
        send_frequency_hz: u8,
        subtitle_tracks: &[WebvttTrack],
    ) -> std::io::Result<()> {
        write_webvtt_header(
            self,
            max_latency_to_video,
            send_frequency_hz,
            subtitle_tracks,
        )
    }

    fn write_webvtt_payload(
        &mut self,
        track_index: u8,
        chunk_number: u64,
        chunk_version: u8,
        video_offset: Duration,
        webvtt_payload: &str, // TODO: replace with string type that checks for interior NULs
    ) -> std::io::Result<()> {
        write_webvtt_payload(
            self,
            track_index,
            chunk_number,
            chunk_version,
            video_offset,
            webvtt_payload,
        )
    }
}
