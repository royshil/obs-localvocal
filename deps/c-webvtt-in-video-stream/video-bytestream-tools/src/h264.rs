use crate::{
    h26x::{annex_b::WriteNalHeader, NalUnitWrite, NalUnitWriter, RbspWrite, RbspWriter},
    webvtt::{WebvttTrack, WebvttWrite},
};
use byteorder::WriteBytesExt;
use h264_reader::nal::UnitType;
use std::{io::Write, time::Duration};

type Result<T, E = std::io::Error> = std::result::Result<T, E>;

pub mod annex_b;
pub mod avcc;

#[derive(Debug, Clone, Copy)]
pub struct H264NalHeader {
    nal_unit_type: UnitType,
    nal_ref_idc: u8,
}

#[derive(Debug, Clone, Copy)]
pub enum H264NalHeaderError {
    NalRefIdcOutOfRange(u8),
    InvalidNalRefIdcForNalUnitType {
        nal_unit_type: UnitType,
        nal_ref_idc: u8,
    },
    NalUnitTypeOutOfRange(UnitType),
}

impl H264NalHeader {
    pub fn from_nal_unit_type_and_nal_ref_idc(
        nal_unit_type: UnitType,
        nal_ref_idc: u8,
    ) -> Result<Self, H264NalHeaderError> {
        if nal_ref_idc >= 4 {
            return Err(H264NalHeaderError::NalRefIdcOutOfRange(nal_ref_idc));
        }
        match nal_unit_type.id() {
            0 => Err(H264NalHeaderError::NalUnitTypeOutOfRange(nal_unit_type)),
            6 | 9 | 10 | 11 | 12 => {
                if nal_ref_idc == 0 {
                    Ok(Self {
                        nal_unit_type,
                        nal_ref_idc,
                    })
                } else {
                    Err(H264NalHeaderError::InvalidNalRefIdcForNalUnitType {
                        nal_unit_type,
                        nal_ref_idc,
                    })
                }
            }
            5 => {
                if nal_ref_idc != 0 {
                    Ok(Self {
                        nal_unit_type,
                        nal_ref_idc,
                    })
                } else {
                    Err(H264NalHeaderError::InvalidNalRefIdcForNalUnitType {
                        nal_unit_type,
                        nal_ref_idc,
                    })
                }
            }
            32.. => Err(H264NalHeaderError::NalUnitTypeOutOfRange(nal_unit_type)),
            _ => Ok(Self {
                nal_unit_type,
                nal_ref_idc,
            }),
        }
    }

    fn as_header_byte(&self) -> u8 {
        self.nal_ref_idc << 5 | self.nal_unit_type.id()
    }
}

impl<W: ?Sized + Write> WriteNalHeader<W> for H264NalHeader {
    fn write_to(self, writer: &mut W) -> crate::h26x::Result<()> {
        writer.write_u8(self.as_header_byte())
    }
}

pub trait H264ByteStreamWrite<W: ?Sized + Write> {
    type Writer: NalUnitWrite<W>;
    fn start_write_nal_unit(self) -> Result<Self::Writer>;
}

impl<W: Write> H264ByteStreamWrite<W> for W {
    type Writer = H264NalUnitWriter<W>;

    fn start_write_nal_unit(self) -> Result<Self::Writer> {
        Ok(H264NalUnitWriter(NalUnitWriter::new(self)))
    }
}

pub struct H264NalUnitWriter<W: ?Sized + Write>(NalUnitWriter<W>);
pub struct H264RbspWriter<W: ?Sized + Write>(RbspWriter<W>);

impl<W: Write> NalUnitWrite<W> for H264NalUnitWriter<W> {
    type Writer = H264RbspWriter<W>;
    type NalHeader = H264NalHeader;

    fn write_nal_header(mut self, nal_header: H264NalHeader) -> Result<H264RbspWriter<W>> {
        self.0.inner.write_u8(nal_header.as_header_byte())?;
        Ok(H264RbspWriter(RbspWriter::new(self.0.inner)))
    }
}

impl<W: Write> RbspWrite<W> for H264RbspWriter<W> {
    type Writer = W;

    fn finish_rbsp(self) -> crate::h26x::Result<Self::Writer> {
        self.0.finish_rbsp()
    }
}

impl<W: Write + ?Sized> WebvttWrite for H264RbspWriter<W> {
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

#[cfg(test)]
mod tests {
    use crate::{
        h264::{H264NalHeader, H264NalUnitWriter},
        h26x::{NalUnitWrite, NalUnitWriter, RbspWrite},
        webvtt::{WebvttWrite, PAYLOAD_GUID, USER_DATA_UNREGISTERED},
    };
    use byteorder::{BigEndian, ReadBytesExt};
    use h264_reader::nal::{Nal, RefNal, UnitType};
    use std::{io::Read, time::Duration};

    #[test]
    fn check_webvtt_sei() {
        let mut writer = vec![];

        let nalu_writer = H264NalUnitWriter(NalUnitWriter::new(&mut writer));
        let nal_unit_type = h264_reader::nal::UnitType::SEI;
        let nal_ref_idc = 0;
        let nal_header =
            H264NalHeader::from_nal_unit_type_and_nal_ref_idc(nal_unit_type, nal_ref_idc).unwrap();
        let mut payload_writer = nalu_writer.write_nal_header(nal_header).unwrap();
        let track_index = 0;
        let chunk_number = 1;
        let chunk_version = 0;
        let video_offset = Duration::from_millis(200);
        let webvtt_payload = "Some unverified data";
        payload_writer
            .write_webvtt_payload(
                track_index,
                chunk_number,
                chunk_version,
                video_offset,
                webvtt_payload,
            )
            .unwrap();
        payload_writer.finish_rbsp().unwrap();
        assert!(&writer[3..19] == PAYLOAD_GUID.as_bytes());

        let nal = RefNal::new(&writer, &[], true);
        assert!(nal.is_complete());
        assert!(nal.header().unwrap().nal_unit_type() == UnitType::SEI);
        let mut byte_reader = nal.rbsp_bytes();

        assert!(usize::from(byte_reader.read_u8().unwrap()) == USER_DATA_UNREGISTERED);
        let mut length = 0;
        loop {
            let byte = byte_reader.read_u8().unwrap();
            length += usize::from(byte);
            if byte != 255 {
                break;
            }
        }
        assert!(length + 1 == byte_reader.clone().bytes().count());
        byte_reader.read_u128::<BigEndian>().unwrap();
        assert!(track_index == byte_reader.read_u8().unwrap());
        assert!(chunk_number == byte_reader.read_u64::<BigEndian>().unwrap());
        assert!(chunk_version == byte_reader.read_u8().unwrap());
        assert!(
            u16::try_from(video_offset.as_millis()).unwrap()
                == byte_reader.read_u16::<BigEndian>().unwrap()
        );
        println!("{writer:02x?}");
    }

    #[test]
    fn check_webvtt_multi_sei() {
        let mut writer = vec![];

        let nalu_writer = H264NalUnitWriter(NalUnitWriter::new(&mut writer));
        let nal_unit_type = h264_reader::nal::UnitType::SEI;
        let nal_ref_idc = 0;
        let nal_header =
            H264NalHeader::from_nal_unit_type_and_nal_ref_idc(nal_unit_type, nal_ref_idc).unwrap();
        let mut payload_writer = nalu_writer.write_nal_header(nal_header).unwrap();
        let track_index = 0;
        let chunk_number = 1;
        let chunk_version = 0;
        let video_offset = Duration::from_millis(200);
        let webvtt_payload = "Some unverified data";
        payload_writer
            .write_webvtt_payload(
                track_index,
                chunk_number,
                chunk_version,
                video_offset,
                webvtt_payload,
            )
            .unwrap();
        payload_writer
            .write_webvtt_payload(1, 1, 0, video_offset, "Something else")
            .unwrap();
        payload_writer.finish_rbsp().unwrap();
        assert!(&writer[3..19] == PAYLOAD_GUID.as_bytes());

        let nal = RefNal::new(&writer, &[], true);
        assert!(nal.is_complete());
        assert!(nal.header().unwrap().nal_unit_type() == UnitType::SEI);
        let mut byte_reader = nal.rbsp_bytes();

        assert!(usize::from(byte_reader.read_u8().unwrap()) == USER_DATA_UNREGISTERED);
        let mut _length = 0;
        loop {
            let byte = byte_reader.read_u8().unwrap();
            _length += usize::from(byte);
            if byte != 255 {
                break;
            }
        }
        byte_reader.read_u128::<BigEndian>().unwrap();
        assert!(track_index == byte_reader.read_u8().unwrap());
        assert!(chunk_number == byte_reader.read_u64::<BigEndian>().unwrap());
        assert!(chunk_version == byte_reader.read_u8().unwrap());
        assert!(
            u16::try_from(video_offset.as_millis()).unwrap()
                == byte_reader.read_u16::<BigEndian>().unwrap()
        );
        println!("{writer:02x?}");
    }
}
