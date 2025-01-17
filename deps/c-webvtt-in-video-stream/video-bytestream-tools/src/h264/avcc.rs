use crate::{
    h264::{H264ByteStreamWrite, H264NalHeader},
    h26x::{NalUnitWrite, NalUnitWriter, RbspWrite, Result},
    webvtt::{WebvttTrack, WebvttWrite},
};
use byteorder::{BigEndian, WriteBytesExt};
use std::{io::Write, time::Duration};
use thiserror::Error;

use super::{H264NalUnitWriter, H264RbspWriter};

const AVCC_MAX_LENGTH: [usize; 4] = [0xff, 0xff_ff, 0, 0xff_ff_ff_ff];

pub struct AVCCWriter<W: ?Sized + Write> {
    length_size: usize,
    inner: W,
}

#[derive(Error, Debug)]
#[error("AVCC length of {0} is unsupported")]
pub struct InvalidLengthError(pub usize);

#[derive(Error, Debug)]
#[error("Tried to write {required} bytes which exceeds the max size of {max}")]
pub struct MaxNalUnitSizeExceededError {
    max: usize,
    required: usize,
}

impl<W: Write> AVCCWriter<W> {
    pub fn new(length_size: usize, inner: W) -> Result<Self, InvalidLengthError> {
        match length_size {
            1 | 2 | 4 => Ok(Self { length_size, inner }),
            _ => Err(InvalidLengthError(length_size)),
        }
    }
}

impl<W: Write> H264ByteStreamWrite<W> for AVCCWriter<W> {
    type Writer = AVCCNalUnitWriter<AVCCWriterBuffer<W>>;

    fn start_write_nal_unit(self) -> Result<AVCCNalUnitWriter<AVCCWriterBuffer<W>>> {
        Ok(AVCCNalUnitWriter {
            inner: H264NalUnitWriter(NalUnitWriter::new(AVCCWriterBuffer::new(self))),
        })
    }
}

pub struct AVCCWriterBuffer<W: ?Sized + Write> {
    avcc_buffer: Vec<u8>,
    avcc_writer: AVCCWriter<W>,
}

impl<W: Write> AVCCWriterBuffer<W> {
    fn new(avcc_writer: AVCCWriter<W>) -> Self {
        Self {
            avcc_buffer: vec![],
            avcc_writer,
        }
    }

    fn finish(mut self) -> Result<AVCCWriter<W>> {
        match self.avcc_writer.length_size {
            1 => self.write_u8(self.avcc_buffer.len().try_into().unwrap())?,
            2 => self.write_u16::<BigEndian>(self.avcc_buffer.len().try_into().unwrap())?,
            4 => self.write_u32::<BigEndian>(self.avcc_buffer.len().try_into().unwrap())?,
            _ => unreachable!(),
        }
        self.avcc_writer.inner.write_all(&self.avcc_buffer)?;
        Ok(self.avcc_writer)
    }
}

impl<W: ?Sized + Write> Write for AVCCWriterBuffer<W> {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let length = self.avcc_buffer.len();
        let additional_length = buf.len();
        if length + additional_length > AVCC_MAX_LENGTH[self.avcc_writer.length_size] {
            Err(std::io::Error::other(MaxNalUnitSizeExceededError {
                max: AVCC_MAX_LENGTH[self.avcc_writer.length_size],
                required: length + additional_length,
            }))
        } else {
            self.avcc_buffer.write(buf)
        }
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

pub struct AVCCNalUnitWriter<W: ?Sized + Write> {
    inner: H264NalUnitWriter<W>,
}

impl<W: Write> NalUnitWrite<W> for AVCCNalUnitWriter<AVCCWriterBuffer<W>> {
    type Writer = AVCCRbspWriter<AVCCWriterBuffer<W>>;
    type NalHeader = H264NalHeader;

    fn write_nal_header(
        self,
        nal_header: Self::NalHeader,
    ) -> Result<AVCCRbspWriter<AVCCWriterBuffer<W>>> {
        self.inner.write_nal_header(nal_header).map(AVCCRbspWriter)
    }
}

pub struct AVCCRbspWriter<W: ?Sized + Write>(H264RbspWriter<W>);

impl<W: Write> RbspWrite<W> for AVCCRbspWriter<AVCCWriterBuffer<W>> {
    type Writer = AVCCWriter<W>;

    fn finish_rbsp(self) -> Result<Self::Writer> {
        let buffer = self.0.finish_rbsp()?;
        buffer.finish()
    }
}

impl<W: Write + ?Sized> WebvttWrite for AVCCRbspWriter<W> {
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
