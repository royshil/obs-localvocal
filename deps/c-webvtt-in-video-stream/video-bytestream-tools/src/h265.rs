use crate::{
    h26x::{annex_b::WriteNalHeader, NalUnitWrite, NalUnitWriter, RbspWrite, RbspWriter},
    webvtt::{WebvttTrack, WebvttWrite},
};
use bitstream_io::{BigEndian, BitWrite, BitWriter};
use std::{io::Write, time::Duration};

type Result<T, E = std::io::Error> = std::result::Result<T, E>;

pub mod annex_b;

#[derive(Debug, Clone, Copy)]
pub enum UnitType {
    TrailN,
    TrailR,
    TsaN,
    TsaR,
    StsaN,
    StsaR,
    RadlN,
    RadlR,
    RaslN,
    RaslR,
    RsvVclN10,
    RsvVclN12,
    RsvVclN14,
    RsvVclR11,
    RsvVclR13,
    RsvVclR15,
    BlaWLp,
    BlaWRadl,
    BlaNLp,
    IdrWRadl,
    IdrNLp,
    CraNut,
    RsvIrapVcl22,
    RsvIrapVcl23,
    RsvVcl24,
    RsvVcl25,
    RsvVcl26,
    RsvVcl27,
    RsvVcl28,
    RsvVcl29,
    RsvVcl30,
    RsvVcl31,
    VpsNut,
    SpsNut,
    PpsNut,
    AudNut,
    EosNut,
    EobNut,
    FdNut,
    PrefixSeiNut,
    SuffixSeiNut,
    RsvNvcl41,
    RsvNvcl42,
    RsvNvcl43,
    RsvNvcl44,
    RsvNvcl45,
    RsvNvcl46,
    RsvNvcl47,
    Unspec48,
    Unspec49,
    Unspec50,
    Unspec51,
    Unspec52,
    Unspec53,
    Unspec54,
    Unspec55,
    Unspec56,
    Unspec57,
    Unspec58,
    Unspec59,
    Unspec60,
    Unspec61,
    Unspec62,
    Unspec63,
}

impl UnitType {
    fn id(self) -> u8 {
        match self {
            UnitType::TrailN => 0,
            UnitType::TrailR => 1,
            UnitType::TsaN => 2,
            UnitType::TsaR => 3,
            UnitType::StsaN => 4,
            UnitType::StsaR => 5,
            UnitType::RadlN => 6,
            UnitType::RadlR => 7,
            UnitType::RaslN => 8,
            UnitType::RaslR => 9,
            UnitType::RsvVclN10 => 10,
            UnitType::RsvVclN12 => 11,
            UnitType::RsvVclN14 => 12,
            UnitType::RsvVclR11 => 13,
            UnitType::RsvVclR13 => 14,
            UnitType::RsvVclR15 => 15,
            UnitType::BlaWLp => 16,
            UnitType::BlaWRadl => 17,
            UnitType::BlaNLp => 18,
            UnitType::IdrWRadl => 19,
            UnitType::IdrNLp => 20,
            UnitType::CraNut => 21,
            UnitType::RsvIrapVcl22 => 22,
            UnitType::RsvIrapVcl23 => 23,
            UnitType::RsvVcl24 => 24,
            UnitType::RsvVcl25 => 25,
            UnitType::RsvVcl26 => 26,
            UnitType::RsvVcl27 => 27,
            UnitType::RsvVcl28 => 28,
            UnitType::RsvVcl29 => 29,
            UnitType::RsvVcl30 => 30,
            UnitType::RsvVcl31 => 31,
            UnitType::VpsNut => 32,
            UnitType::SpsNut => 33,
            UnitType::PpsNut => 34,
            UnitType::AudNut => 35,
            UnitType::EosNut => 36,
            UnitType::EobNut => 37,
            UnitType::FdNut => 38,
            UnitType::PrefixSeiNut => 39,
            UnitType::SuffixSeiNut => 40,
            UnitType::RsvNvcl41 => 41,
            UnitType::RsvNvcl42 => 42,
            UnitType::RsvNvcl43 => 43,
            UnitType::RsvNvcl44 => 44,
            UnitType::RsvNvcl45 => 45,
            UnitType::RsvNvcl46 => 46,
            UnitType::RsvNvcl47 => 47,
            UnitType::Unspec48 => 48,
            UnitType::Unspec49 => 49,
            UnitType::Unspec50 => 50,
            UnitType::Unspec51 => 51,
            UnitType::Unspec52 => 52,
            UnitType::Unspec53 => 53,
            UnitType::Unspec54 => 54,
            UnitType::Unspec55 => 55,
            UnitType::Unspec56 => 56,
            UnitType::Unspec57 => 57,
            UnitType::Unspec58 => 58,
            UnitType::Unspec59 => 59,
            UnitType::Unspec60 => 60,
            UnitType::Unspec61 => 61,
            UnitType::Unspec62 => 62,
            UnitType::Unspec63 => 63,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct H265NalHeader {
    nal_unit_type: UnitType,
    nuh_layer_id: u8,
    nuh_temporal_id: u8,
}

#[derive(Debug, Clone, Copy)]
pub enum H265NalHeaderError {
    NuhLayerIdOutOfRange(u8),
    NuhTemporalIdOutOfRange(u8),
}

impl H265NalHeader {
    pub fn from_nal_unit_type_and_nuh_ids(
        nal_unit_type: UnitType,
        nuh_layer_id: u8,
        nuh_temporal_id: u8,
    ) -> Result<Self, H265NalHeaderError> {
        if nuh_layer_id >= 0b100_0000 {
            return Err(H265NalHeaderError::NuhLayerIdOutOfRange(nuh_layer_id));
        }
        if nuh_temporal_id >= (0b1000 - 1) {
            return Err(H265NalHeaderError::NuhTemporalIdOutOfRange(nuh_temporal_id));
        }
        Ok(Self {
            nal_unit_type,
            nuh_layer_id,
            nuh_temporal_id,
        })
    }

    fn as_header_bytes(&self) -> Result<[u8; 2]> {
        let mut output = [0u8; 2];
        let mut writer = BitWriter::endian(&mut output[..], BigEndian);
        writer.write(1, 0)?;
        writer.write(6, self.nal_unit_type.id())?;
        writer.write(6, self.nuh_layer_id)?;
        writer.write(3, self.nuh_temporal_id + 1)?;
        assert!(writer.into_unwritten() == (0, 0));
        Ok(output)
    }
}

impl<W: ?Sized + Write> WriteNalHeader<W> for H265NalHeader {
    fn write_to(self, writer: &mut W) -> crate::h26x::Result<()> {
        writer.write_all(&self.as_header_bytes()?[..])
    }
}

pub trait H265ByteStreamWrite<W: ?Sized + Write> {
    type Writer: NalUnitWrite<W>;
    fn start_write_nal_unit(self) -> Result<Self::Writer>;
}

impl<W: Write> H265ByteStreamWrite<W> for W {
    type Writer = H265NalUnitWriter<W>;

    fn start_write_nal_unit(self) -> Result<Self::Writer> {
        Ok(H265NalUnitWriter(NalUnitWriter::new(self)))
    }
}

pub struct H265NalUnitWriter<W: ?Sized + Write>(NalUnitWriter<W>);
pub struct H265RbspWriter<W: ?Sized + Write>(RbspWriter<W>);

impl<W: Write> NalUnitWrite<W> for H265NalUnitWriter<W> {
    type Writer = H265RbspWriter<W>;
    type NalHeader = H265NalHeader;

    fn write_nal_header(mut self, nal_header: H265NalHeader) -> Result<H265RbspWriter<W>> {
        self.0.inner.write_all(&nal_header.as_header_bytes()?[..])?;
        Ok(H265RbspWriter(RbspWriter::new(self.0.inner)))
    }
}

impl<W: Write> RbspWrite<W> for H265RbspWriter<W> {
    type Writer = W;

    fn finish_rbsp(self) -> crate::h26x::Result<Self::Writer> {
        self.0.finish_rbsp()
    }
}

impl<W: Write + ?Sized> WebvttWrite for H265RbspWriter<W> {
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
        h265::{H265NalHeader, H265NalUnitWriter, UnitType},
        h26x::{NalUnitWrite, NalUnitWriter, RbspWrite},
        webvtt::{WebvttWrite, PAYLOAD_GUID, USER_DATA_UNREGISTERED},
    };
    use byteorder::{BigEndian, ReadBytesExt, WriteBytesExt};
    use std::{
        collections::VecDeque,
        io::{ErrorKind, Read},
        time::Duration,
    };

    #[derive(Clone)]
    pub(crate) struct RbspReader<R: ?Sized + Read> {
        last_read: VecDeque<u8>,
        inner: R,
    }

    impl<R: Read> RbspReader<R> {
        pub fn new(inner: R) -> Self {
            RbspReader {
                last_read: VecDeque::new(),
                inner,
            }
        }
    }

    impl<R: Read> Read for RbspReader<R> {
        fn read(&mut self, mut buf: &mut [u8]) -> std::io::Result<usize> {
            let mut read = 0;
            while !buf.is_empty() {
                let res = self.inner.read_u8();
                let byte = match res {
                    Ok(byte) => byte,
                    Err(err) if err.kind() == ErrorKind::UnexpectedEof => return Ok(0),
                    Err(err) => return Err(err),
                };
                let mut last_read_iter = self.last_read.iter();
                if last_read_iter.next() == Some(&0)
                    && last_read_iter.next() == Some(&0)
                    && byte == 3
                {
                    self.last_read.clear();
                    continue;
                }
                if self.last_read.len() > 1 {
                    self.last_read.pop_front();
                }
                read += 1;
                self.last_read.push_back(byte);
                buf.write_u8(byte).unwrap();
            }
            Ok(read)
        }
    }

    #[test]
    fn check_webvtt_sei() {
        let mut writer = vec![];

        let nalu_writer = H265NalUnitWriter(NalUnitWriter::new(&mut writer));
        let nal_unit_type = UnitType::PrefixSeiNut;
        let nuh_layer_id = 0;
        let nuh_temporal_id = 0;
        let nal_header = H265NalHeader::from_nal_unit_type_and_nuh_ids(
            nal_unit_type,
            nuh_layer_id,
            nuh_temporal_id,
        )
        .unwrap();
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

        assert!(&writer[4..20] == PAYLOAD_GUID.as_bytes());
        assert!(writer[0] == nal_unit_type.id() << 1);

        let mut reader = RbspReader::new(&writer[2..]);

        assert!(usize::from(reader.read_u8().unwrap()) == USER_DATA_UNREGISTERED);
        let mut length = 0;
        loop {
            let byte = reader.read_u8().unwrap();
            length += usize::from(byte);
            if byte != 255 {
                break;
            }
        }
        assert!(dbg!(length + 1) == dbg!(reader.clone().bytes().count()));
        reader.read_u128::<BigEndian>().unwrap();
        assert!(track_index == reader.read_u8().unwrap());
        assert!(chunk_number == reader.read_u64::<BigEndian>().unwrap());
        assert!(chunk_version == reader.read_u8().unwrap());
        assert!(
            u16::try_from(video_offset.as_millis()).unwrap()
                == reader.read_u16::<BigEndian>().unwrap()
        );
        println!("{writer:02x?}");
    }

    #[test]
    fn check_webvtt_multi_sei() {
        let mut writer = vec![];

        let nalu_writer = H265NalUnitWriter(NalUnitWriter::new(&mut writer));
        let nal_unit_type = UnitType::PrefixSeiNut;
        let nuh_layer_id = 0;
        let nuh_temporal_id = 0;
        let nal_header = H265NalHeader::from_nal_unit_type_and_nuh_ids(
            nal_unit_type,
            nuh_layer_id,
            nuh_temporal_id,
        )
        .unwrap();
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

        assert!(&writer[4..20] == PAYLOAD_GUID.as_bytes());
        assert!(writer[0] == nal_unit_type.id() << 1);

        let mut reader = RbspReader::new(&writer[2..]);

        assert!(usize::from(reader.read_u8().unwrap()) == USER_DATA_UNREGISTERED);
        let mut _length = 0;
        loop {
            let byte = reader.read_u8().unwrap();
            _length += usize::from(byte);
            if byte != 255 {
                break;
            }
        }
        reader.read_u128::<BigEndian>().unwrap();
        assert!(track_index == reader.read_u8().unwrap());
        assert!(chunk_number == reader.read_u64::<BigEndian>().unwrap());
        assert!(chunk_version == reader.read_u8().unwrap());
        assert!(
            u16::try_from(video_offset.as_millis()).unwrap()
                == reader.read_u16::<BigEndian>().unwrap()
        );
        println!("{writer:02x?}");
    }
}
