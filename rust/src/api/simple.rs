use base64::prelude::{Engine, BASE64_URL_SAFE_NO_PAD};
use std::fs::File;
use rusty_chromaprint::{Configuration, FingerprintCompressor, Fingerprinter};
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use std::io::Read;
use symphonia::core::audio::SampleBuffer;

#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_audio_pcm(path: String, max_seconds: Option<f64>) -> Result<Vec<f32>, String> {
    let src = File::open(&path).map_err(|e| format!("Failed to open file: {}", e))?;
    let mss = MediaSourceStream::new(Box::new(src), Default::default());

    let mut hint = Hint::new();
    let extension = std::path::Path::new(&path)
        .extension()
        .and_then(|ext| ext.to_str());
    if let Some(ext) = extension {
        hint.with_extension(ext);
    }

    let meta_opts: MetadataOptions = Default::default();
    let fmt_opts: FormatOptions = Default::default();

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &fmt_opts, &meta_opts)
        .map_err(|e| format!("Failed to probe file: {}", e))?;

    let mut format = probed.format;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .ok_or_else(|| "No supported audio track found".to_string())?;

    let dec_opts: DecoderOptions = Default::default();
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &dec_opts)
        .map_err(|e| format!("Failed to create decoder: {}", e))?;

    let track_id = track.id;
    let mut samples = Vec::new();
    let mut total_samples_limit = None;

    loop {
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(Error::IoError(_)) => break,
            Err(err) => return Err(format!("Error reading packet: {}", err)),
        };

        if packet.track_id() != track_id {
            continue;
        }

        let decoded = match decoder.decode(&packet) {
            Ok(decoded) => decoded,
            Err(Error::DecodeError(_)) => continue,
            Err(err) => return Err(format!("Error decoding packet: {}", err)),
        };

        if total_samples_limit.is_none() {
            if let Some(secs) = max_seconds {
                let spec = decoded.spec();
                let frame_count = (secs * spec.rate as f64).floor() as usize;
                total_samples_limit = Some(frame_count * spec.channels.count());
            }
        }

        let mut sample_buf = SampleBuffer::<f32>::new(
            decoded.capacity() as u64,
            *decoded.spec(),
        );
        sample_buf.copy_interleaved_ref(decoded);

        let new_samples = sample_buf.samples();
        if let Some(limit) = total_samples_limit {
            let current_len = samples.len();
            if current_len + new_samples.len() >= limit {
                let take = limit - current_len;
                samples.extend_from_slice(&new_samples[..take]);
                break;
            }
        }
        
        samples.extend_from_slice(new_samples);
    }

    Ok(samples)
}

#[flutter_rust_bridge::frb]
pub fn get_fingerprint_raw(path: String, sample_rate: u32, channels: u32) -> Result<String, String> {
    let fingerprint = get_fingerprint_words(path, sample_rate, channels)?;
    let config = Configuration::preset_test2();
    let compressor = FingerprintCompressor::from(&config);
    let compressed = compressor.compress(&fingerprint);
    Ok(BASE64_URL_SAFE_NO_PAD.encode(compressed))
}

fn get_fingerprint_words(
    path: String,
    sample_rate: u32,
    channels: u32,
) -> Result<Vec<u32>, String> {
    let mut file = File::open(&path).map_err(|e| format!("Failed to open file: {}", e))?;
    let mut data = Vec::new();
    file.read_to_end(&mut data).map_err(|e| format!("Failed to read file: {}", e))?;

    let samples: Vec<i16> = data
        .chunks_exact(2)
        .map(|chunk| i16::from_le_bytes([chunk[0], chunk[1]]))
        .collect();

    let mut printer = Fingerprinter::new(&Configuration::preset_test2());
    printer.start(sample_rate, channels).map_err(|e| format!("Failed to start printer: {:?}", e))?;
    printer.consume(&samples);
    printer.finish();
    
    let fingerprint = printer.fingerprint();
    Ok(fingerprint.to_vec())
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}
