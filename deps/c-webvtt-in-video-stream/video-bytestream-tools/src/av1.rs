use crate::webvtt::{
    write_webvtt_header, write_webvtt_payload, CountingSink, WebvttTrack, WebvttWrite,
};
use bitstream_io::{BigEndian, BitWrite, BitWriter};
use byteorder::WriteBytesExt;
use std::{
    io::{Cursor, Write},
    time::Duration,
};

type Result<T, E = std::io::Error> = std::result::Result<T, E>;

pub trait WriteLeb128Ext: BitWrite {
    fn write_leb128(&mut self, mut val: u32) -> std::io::Result<()> {
        loop {
            let bits = u8::try_from(val & 0b111_1111).unwrap();
            val >>= 7;
            self.write_bit(val != 0)?;
            self.write(7, bits)?;
            if val == 0 {
                break;
            }
        }
        Ok(())
    }
}

impl<W: BitWrite + ?Sized> WriteLeb128Ext for W {}

#[derive(Debug, Clone, Copy)]
pub struct OBUHeaderWithSize {
    obu_type: OBUType,
    obu_size: Option<u32>,
    obu_extension_header: Option<OBUExtensionHeader>,
}

#[derive(Debug, Clone, Copy)]
pub enum OBUType {
    Reserved0,
    SequenceHeader,
    TemporalDelimiter,
    FrameHeader,
    TileGroup,
    Metadata,
    Frame,
    RedundantFrameHeader,
    TileList,
    Reserved9,
    Reserved10,
    Reserved11,
    Reserved12,
    Reserved13,
    Reserved14,
    Padding,
}

#[derive(Debug, Clone, Copy)]
pub enum MetadataType {
    ReservedForAOMUse,
    HdrCll,
    HdrMdcv,
    Scalability,
    ItutT35,
    Timecode,
    UnregisteredPrivate6,
    UnregisteredPrivate7,
    UnregisteredPrivate8,
    UnregisteredPrivate9,
    UnregisteredPrivate10,
    UnregisteredPrivate11,
    UnregisteredPrivate12,
    UnregisteredPrivate13,
    UnregisteredPrivate14,
    UnregisteredPrivate15,
    UnregisteredPrivate16,
    UnregisteredPrivate17,
    UnregisteredPrivate18,
    UnregisteredPrivate19,
    UnregisteredPrivate20,
    UnregisteredPrivate21,
    UnregisteredPrivate22,
    UnregisteredPrivate23,
    UnregisteredPrivate24,
    UnregisteredPrivate25,
    UnregisteredPrivate26,
    UnregisteredPrivate27,
    UnregisteredPrivate28,
    UnregisteredPrivate29,
    UnregisteredPrivate30,
    UnregisteredPrivate31,
}

#[derive(Debug, Clone, Copy)]
pub struct OBUExtensionHeader {
    temporal_id: u8,
    spatial_id: u8,
}

impl OBUHeaderWithSize {
    pub fn new(
        obu_type: OBUType,
        obu_size: Option<u32>,
        obu_extension_header: Option<OBUExtensionHeader>,
    ) -> Self {
        Self {
            obu_type,
            obu_size,
            obu_extension_header,
        }
    }

    fn as_header_bytes(self, buffer: &mut [u8; 10]) -> Result<&[u8]> {
        let mut cursor = Cursor::new(&mut buffer[..]);
        let mut writer = BitWriter::endian(&mut cursor, BigEndian);
        writer.write(1, 0)?;
        writer.write(4, self.obu_type.id())?;
        writer.write_bit(self.obu_extension_header.is_some())?;
        writer.write_bit(self.obu_size.is_some())?;
        writer.write(1, 0)?;
        if let Some(extension_header) = self.obu_extension_header {
            writer.write(3, extension_header.temporal_id)?;
            writer.write(2, extension_header.spatial_id)?;
            writer.write(3, 0)?;
        }
        if let Some(size) = self.obu_size {
            writer.write_leb128(size)?;
        }
        assert!(writer.into_unwritten() == (0, 0));
        let written = usize::try_from(cursor.position()).unwrap();
        Ok(&buffer[..written])
    }
}

impl OBUType {
    pub fn id(self) -> u8 {
        match self {
            OBUType::Reserved0 => 0,
            OBUType::SequenceHeader => 1,
            OBUType::TemporalDelimiter => 2,
            OBUType::FrameHeader => 3,
            OBUType::TileGroup => 4,
            OBUType::Metadata => 5,
            OBUType::Frame => 6,
            OBUType::RedundantFrameHeader => 7,
            OBUType::TileList => 8,
            OBUType::Reserved9 => 9,
            OBUType::Reserved10 => 10,
            OBUType::Reserved11 => 11,
            OBUType::Reserved12 => 12,
            OBUType::Reserved13 => 13,
            OBUType::Reserved14 => 14,
            OBUType::Padding => 15,
        }
    }
}

impl MetadataType {
    fn id(self) -> u32 {
        match self {
            MetadataType::ReservedForAOMUse => 0,
            MetadataType::HdrCll => 1,
            MetadataType::HdrMdcv => 2,
            MetadataType::Scalability => 3,
            MetadataType::ItutT35 => 4,
            MetadataType::Timecode => 5,
            MetadataType::UnregisteredPrivate6 => 6,
            MetadataType::UnregisteredPrivate7 => 7,
            MetadataType::UnregisteredPrivate8 => 8,
            MetadataType::UnregisteredPrivate9 => 9,
            MetadataType::UnregisteredPrivate10 => 10,
            MetadataType::UnregisteredPrivate11 => 11,
            MetadataType::UnregisteredPrivate12 => 12,
            MetadataType::UnregisteredPrivate13 => 13,
            MetadataType::UnregisteredPrivate14 => 14,
            MetadataType::UnregisteredPrivate15 => 15,
            MetadataType::UnregisteredPrivate16 => 16,
            MetadataType::UnregisteredPrivate17 => 17,
            MetadataType::UnregisteredPrivate18 => 18,
            MetadataType::UnregisteredPrivate19 => 19,
            MetadataType::UnregisteredPrivate20 => 20,
            MetadataType::UnregisteredPrivate21 => 21,
            MetadataType::UnregisteredPrivate22 => 22,
            MetadataType::UnregisteredPrivate23 => 23,
            MetadataType::UnregisteredPrivate24 => 24,
            MetadataType::UnregisteredPrivate25 => 25,
            MetadataType::UnregisteredPrivate26 => 26,
            MetadataType::UnregisteredPrivate27 => 27,
            MetadataType::UnregisteredPrivate28 => 28,
            MetadataType::UnregisteredPrivate29 => 29,
            MetadataType::UnregisteredPrivate30 => 30,
            MetadataType::UnregisteredPrivate31 => 31,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub enum OBUExtensionHeaderError {
    TemporalIdOutOfRange(u8),
    SpatialIdOutOfRange(u8),
}

impl OBUExtensionHeader {
    pub fn new(temporal_id: u8, spatial_id: u8) -> Result<Self, OBUExtensionHeaderError> {
        if temporal_id > 0b111 {
            return Err(OBUExtensionHeaderError::TemporalIdOutOfRange(temporal_id));
        }
        if spatial_id > 0b11 {
            return Err(OBUExtensionHeaderError::SpatialIdOutOfRange(spatial_id));
        }
        Ok(Self {
            temporal_id,
            spatial_id,
        })
    }
}

pub struct OBUWriter<W: ?Sized + Write>(W);

impl<W: Write> OBUWriter<W> {
    pub fn new(inner: W) -> Self {
        Self(inner)
    }
}

impl<W: ?Sized + Write> OBUWriter<W> {
    fn write_obu_header(&mut self, obu_header: OBUHeaderWithSize) -> Result<()> {
        let mut buffer = [0u8; 10];
        let header_bytes = obu_header.as_header_bytes(&mut buffer)?;
        self.0.write_all(header_bytes)
    }

    fn finish_payload(&mut self) -> Result<()> {
        self.0.write_u8(0b1000_0000)
    }
}

impl<W: Write + ?Sized> WebvttWrite for OBUWriter<W> {
    fn write_webvtt_header(
        &mut self,
        max_latency_to_video: Duration,
        send_frequency_hz: u8,
        subtitle_tracks: &[WebvttTrack],
    ) -> std::io::Result<()> {
        fn inner<W: ?Sized + Write>(
            writer: &mut W,
            max_latency_to_video: Duration,
            send_frequency_hz: u8,
            subtitle_tracks: &[WebvttTrack],
        ) -> std::io::Result<()> {
            write_webvtt_header(
                writer,
                max_latency_to_video,
                send_frequency_hz,
                subtitle_tracks,
                |write, _size| {
                    let mut writer = BitWriter::endian(write, BigEndian);
                    writer.write_leb128(MetadataType::UnregisteredPrivate6.id())
                },
            )
        }
        let mut count = CountingSink::new();
        inner(
            &mut count,
            max_latency_to_video,
            send_frequency_hz,
            subtitle_tracks,
        )?;
        let header = OBUHeaderWithSize::new(
            OBUType::Metadata,
            Some(u32::try_from(count.count()).unwrap() + 1),
            None,
        );
        self.write_obu_header(header)?;
        inner(
            &mut self.0,
            max_latency_to_video,
            send_frequency_hz,
            subtitle_tracks,
        )?;
        self.finish_payload()
    }

    fn write_webvtt_payload(
        &mut self,
        track_index: u8,
        chunk_number: u64,
        chunk_version: u8,
        video_offset: Duration,
        webvtt_payload: &str, // TODO: replace with string type that checks for interior NULs
    ) -> std::io::Result<()> {
        fn inner<W: ?Sized + Write>(
            writer: &mut W,
            track_index: u8,
            chunk_number: u64,
            chunk_version: u8,
            video_offset: Duration,
            webvtt_payload: &str,
        ) -> std::io::Result<()> {
            write_webvtt_payload(
                writer,
                track_index,
                chunk_number,
                chunk_version,
                video_offset,
                webvtt_payload,
                |write, _size| {
                    let mut writer = BitWriter::endian(write, BigEndian);
                    writer.write_leb128(MetadataType::UnregisteredPrivate6.id())
                },
            )
        }
        let mut count = CountingSink::new();
        inner(
            &mut count,
            track_index,
            chunk_number,
            chunk_version,
            video_offset,
            webvtt_payload,
        )?;
        let header = OBUHeaderWithSize::new(
            OBUType::Metadata,
            Some(u32::try_from(count.count()).unwrap() + 1),
            None,
        );
        self.write_obu_header(header)?;
        inner(
            &mut self.0,
            track_index,
            chunk_number,
            chunk_version,
            video_offset,
            webvtt_payload,
        )?;
        self.finish_payload()
    }
}
