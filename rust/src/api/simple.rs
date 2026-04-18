use base64::prelude::{Engine, BASE64_URL_SAFE_NO_PAD};
use rubato::Resampler;
use rustfft::num_complex::{Complex, Complex64};
use rustfft::num_traits::Zero;
use rusty_chromaprint::{Configuration, FingerprintCompressor, Fingerprinter};
use std::fs::File;
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use symphonia::core::audio::SampleBuffer;
use std::io::Read;

const MIN_SAMPLE_RATE: u32 = 1000;
const MAX_BUFFER_SIZE: usize = 1024 * 32;
const DEFAULT_TARGET_SAMPLE_RATE: u32 = 11025;
const DEFAULT_FRAME_SIZE: usize = 4096;
const DEFAULT_FRAME_OVERLAP: usize = DEFAULT_FRAME_SIZE - DEFAULT_FRAME_SIZE / 3;
const DEFAULT_FRAME_STRIDE: usize = DEFAULT_FRAME_SIZE - DEFAULT_FRAME_OVERLAP;
const DEFAULT_SPECTRUM_BINS: usize = 1 + DEFAULT_FRAME_SIZE / 2;
const DEFAULT_CHROMA_BANDS: usize = 12;
const DEFAULT_MIN_FREQ: u32 = 28;
const DEFAULT_MAX_FREQ: u32 = 3520;
const DEFAULT_CHROMA_FILTER_COEFFICIENTS: [f64; 5] = [0.25, 0.75, 1.0, 0.75, 0.25];

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

#[flutter_rust_bridge::frb(sync)]
pub fn get_processed_pcm(path: String, sample_rate: u32, channels: u32) -> Result<Vec<f64>, String> {
    let samples = read_pcm_i16(&path)?;
    preprocess_pcm_samples(&samples, sample_rate, channels)
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_fft_spectrum_baseline(
    path: String,
    sample_rate: u32,
    channels: u32,
) -> Result<Vec<f64>, String> {
    let samples = read_pcm_i16(&path)?;
    let processed = preprocess_pcm_samples(&samples, sample_rate, channels)?;
    Ok(compute_fft_spectrum(&processed))
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_chroma_baseline(
    path: String,
    sample_rate: u32,
    channels: u32,
) -> Result<Vec<f64>, String> {
    let samples = read_pcm_i16(&path)?;
    let processed = preprocess_pcm_samples(&samples, sample_rate, channels)?;
    let spectrum = compute_fft_spectrum(&processed);
    Ok(compute_chroma(&spectrum, false))
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_filtered_chroma_baseline(
    path: String,
    sample_rate: u32,
    channels: u32,
) -> Result<Vec<f64>, String> {
    let samples = read_pcm_i16(&path)?;
    let processed = preprocess_pcm_samples(&samples, sample_rate, channels)?;
    let spectrum = compute_fft_spectrum(&processed);
    let chroma = compute_chroma(&spectrum, false);
    Ok(apply_chroma_filter(
        &chroma,
        &DEFAULT_CHROMA_FILTER_COEFFICIENTS,
    ))
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_normalized_chroma_baseline(
    path: String,
    sample_rate: u32,
    channels: u32,
) -> Result<Vec<f64>, String> {
    let samples = read_pcm_i16(&path)?;
    let processed = preprocess_pcm_samples(&samples, sample_rate, channels)?;
    let spectrum = compute_fft_spectrum(&processed);
    let chroma = compute_chroma(&spectrum, false);
    let filtered = apply_chroma_filter(&chroma, &DEFAULT_CHROMA_FILTER_COEFFICIENTS);
    Ok(normalize_chroma_vectors(&filtered, 0.01))
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

fn read_pcm_i16(path: &str) -> Result<Vec<i16>, String> {
    let mut file = File::open(path).map_err(|e| format!("Failed to open file: {}", e))?;
    let mut data = Vec::new();
    file.read_to_end(&mut data)
        .map_err(|e| format!("Failed to read file: {}", e))?;

    if data.len() % 2 != 0 {
        return Err("PCM data length must be divisible by 2".to_string());
    }

    Ok(data
        .chunks_exact(2)
        .map(|chunk| i16::from_le_bytes([chunk[0], chunk[1]]))
        .collect())
}

fn preprocess_pcm_samples(
    samples: &[i16],
    sample_rate: u32,
    channels: u32,
) -> Result<Vec<f64>, String> {
    if channels == 0 {
        return Err("At least one channel is required".to_string());
    }

    if sample_rate <= MIN_SAMPLE_RATE {
        return Err(format!(
            "Sample rate is too low. Required min. {}",
            MIN_SAMPLE_RATE
        ));
    }

    let channels_usize: usize = channels
        .try_into()
        .map_err(|_| "Channel count is too large".to_string())?;
    if samples.len() % channels_usize != 0 {
        return Err("PCM sample count is not divisible by channel count".to_string());
    }

    let mut buffer = vec![0i16; MAX_BUFFER_SIZE].into_boxed_slice();
    let mut buffer_offset = 0usize;
    let mut resampler_input = Vec::<f64>::new();
    let mut processed = Vec::<f64>::new();

    let mut resampler = if sample_rate != DEFAULT_TARGET_SAMPLE_RATE {
        Some(
            rubato::SincFixedIn::new(
                DEFAULT_TARGET_SAMPLE_RATE as f64 / sample_rate as f64,
                1.0,
                rubato::SincInterpolationParameters {
                    sinc_len: 16,
                    f_cutoff: 0.8,
                    oversampling_factor: 128,
                    interpolation: rubato::SincInterpolationType::Nearest,
                    window: rubato::WindowFunction::Blackman,
                },
                MAX_BUFFER_SIZE,
                1,
            )
            .map_err(|e| format!("Cannot construct resampler: {}", e))?,
        )
    } else {
        None
    };

    let available_frames = samples.len() / channels_usize;
    let mut frame_index = 0usize;

    while frame_index < available_frames {
        let available_space = buffer.len() - buffer_offset;
        let frames_to_copy = (available_frames - frame_index).min(available_space);

        let start = frame_index * channels_usize;
        let end = start + frames_to_copy * channels_usize;
        let input = &samples[start..end];

        match channels_usize {
            1 => {
                for &sample in input {
                    buffer[buffer_offset] = sample;
                    buffer_offset += 1;
                }
            }
            2 => {
                for frame in input.chunks_exact(2) {
                    buffer[buffer_offset] =
                        ((i32::from(frame[0]) + i32::from(frame[1])) / 2) as i16;
                    buffer_offset += 1;
                }
            }
            _ => {
                for frame in input.chunks_exact(channels_usize) {
                    let sum: i32 = frame.iter().copied().map(i32::from).sum();
                    let avg = sum / frame.len() as i32;
                    buffer[buffer_offset] = avg as i16;
                    buffer_offset += 1;
                }
            }
        }

        frame_index += frames_to_copy;

        if buffer_offset == buffer.len() {
            flush_preprocess_buffer(
                &buffer[..buffer_offset],
                false,
                &mut resampler_input,
                &mut processed,
                resampler.as_mut(),
            )?;
            buffer_offset = 0;
        }
    }

    if buffer_offset > 0 {
        flush_preprocess_buffer(
            &buffer[..buffer_offset],
            true,
            &mut resampler_input,
            &mut processed,
            resampler.as_mut(),
        )?;
    }

    Ok(processed)
}

fn flush_preprocess_buffer(
    buffer: &[i16],
    is_end: bool,
    resampler_input: &mut Vec<f64>,
    output: &mut Vec<f64>,
    resampler: Option<&mut rubato::SincFixedIn<f64>>,
) -> Result<(), String> {
    for &sample in buffer {
        resampler_input.push(f64::from(sample) / f64::from(i16::MAX));
    }

    if let Some(resampler) = resampler {
        let default_input_frames = resampler.input_frames_next();
        let mut chunk_output = vec![0.0; resampler.output_frames_max()];

        while !resampler_input.is_empty() {
            if resampler_input.len() < resampler.input_frames_next() {
                if is_end {
                    resampler
                        .set_chunk_size(resampler_input.len())
                        .map_err(|e| format!("Cannot update resampler chunk size: {}", e))?;
                } else {
                    break;
                }
            }

            let required_input = resampler.input_frames_next();
            chunk_output.resize(resampler.output_frames_next(), 0.0);
            let (read_samples, written_samples) = resampler
                .process_into_buffer(
                    &[&resampler_input[..required_input]],
                    std::slice::from_mut(&mut chunk_output),
                    None,
                )
                .map_err(|e| format!("Cannot resample audio: {}", e))?;
            resampler_input.drain(..read_samples);
            output.extend_from_slice(&chunk_output[..written_samples]);

            if is_end {
                resampler
                    .set_chunk_size(default_input_frames)
                    .map_err(|e| format!("Cannot restore resampler chunk size: {}", e))?;
            }
        }
    } else {
        output.extend_from_slice(resampler_input);
        resampler_input.clear();
    }

    Ok(())
}

fn compute_fft_spectrum(samples: &[f64]) -> Vec<f64> {
    if samples.len() < DEFAULT_FRAME_SIZE {
        return Vec::new();
    }

    let frame_count = 1 + (samples.len() - DEFAULT_FRAME_SIZE) / DEFAULT_FRAME_STRIDE;
    let mut output = Vec::with_capacity(frame_count * DEFAULT_SPECTRUM_BINS);
    let mut planner = rustfft::FftPlanner::<f64>::new();
    let fft_plan = planner.plan_fft_forward(DEFAULT_FRAME_SIZE);
    let mut fft_buffer = vec![Complex64::zero(); DEFAULT_FRAME_SIZE].into_boxed_slice();
    let mut fft_scratch = vec![Complex::zero(); fft_plan.get_inplace_scratch_len()].into_boxed_slice();
    let window = make_hamming_window(DEFAULT_FRAME_SIZE, 1.0);

    for frame_start in (0..=(samples.len() - DEFAULT_FRAME_SIZE)).step_by(DEFAULT_FRAME_STRIDE) {
        let frame = &samples[frame_start..frame_start + DEFAULT_FRAME_SIZE];
        for (i, (output_sample, input_sample)) in fft_buffer.iter_mut().zip(frame).enumerate() {
            output_sample.re = input_sample * window[i];
            output_sample.im = 0.0;
        }

        fft_plan.process_with_scratch(&mut fft_buffer, &mut fft_scratch);

        for i in 0..DEFAULT_FRAME_SIZE / 2 {
            output.push(fft_buffer[i].norm_sqr());
        }
        output.push(0.0);
    }

    output
}

fn compute_chroma(spectrum: &[f64], interpolate: bool) -> Vec<f64> {
    if spectrum.is_empty() {
        return Vec::new();
    }

    assert_eq!(spectrum.len() % DEFAULT_SPECTRUM_BINS, 0);
    let frame_count = spectrum.len() / DEFAULT_SPECTRUM_BINS;
    let mut output = vec![0.0; frame_count * DEFAULT_CHROMA_BANDS];
    let mut notes = vec![0u8; DEFAULT_FRAME_SIZE].into_boxed_slice();
    let mut notes_frac = vec![0.0; DEFAULT_FRAME_SIZE].into_boxed_slice();

    let min_index = freq_to_index(DEFAULT_MIN_FREQ, DEFAULT_FRAME_SIZE, DEFAULT_TARGET_SAMPLE_RATE).max(1);
    let max_index = freq_to_index(DEFAULT_MAX_FREQ, DEFAULT_FRAME_SIZE, DEFAULT_TARGET_SAMPLE_RATE)
        .min(DEFAULT_FRAME_SIZE / 2);

    for i in min_index..max_index {
        let freq = index_to_freq(i, DEFAULT_FRAME_SIZE, DEFAULT_TARGET_SAMPLE_RATE);
        let octave = freq_to_octave(freq);
        let note = DEFAULT_CHROMA_BANDS as f64 * (octave - octave.floor());
        notes[i] = note.floor() as u8;
        notes_frac[i] = note - note.floor();
    }

    for frame in 0..frame_count {
        let spectrum_offset = frame * DEFAULT_SPECTRUM_BINS;
        let chroma_offset = frame * DEFAULT_CHROMA_BANDS;
        for i in min_index..max_index {
            let energy = spectrum[spectrum_offset + i];
            let note = notes[i] as usize;
            if interpolate {
                let mut note2 = note;
                let mut a = 1.0;
                if notes_frac[i] < 0.5 {
                    note2 = (note + DEFAULT_CHROMA_BANDS - 1) % DEFAULT_CHROMA_BANDS;
                    a = 0.5 + notes_frac[i];
                }
                if notes_frac[i] > 0.5 {
                    note2 = (note + 1) % DEFAULT_CHROMA_BANDS;
                    a = 1.5 - notes_frac[i];
                }
                output[chroma_offset + note] += energy * a;
                output[chroma_offset + note2] += energy * (1.0 - a);
            } else {
                output[chroma_offset + note] += energy;
            }
        }
    }

    output
}

fn apply_chroma_filter(chroma: &[f64], coefficients: &[f64]) -> Vec<f64> {
    if chroma.is_empty() {
        return Vec::new();
    }

    assert_eq!(chroma.len() % DEFAULT_CHROMA_BANDS, 0);
    let frame_count = chroma.len() / DEFAULT_CHROMA_BANDS;
    if frame_count < coefficients.len() {
        return Vec::new();
    }

    let mut output =
        Vec::with_capacity((frame_count - coefficients.len() + 1) * DEFAULT_CHROMA_BANDS);
    let mut buffer = [[0.0; DEFAULT_CHROMA_BANDS]; 8];
    let mut result = [0.0; DEFAULT_CHROMA_BANDS];
    let mut buffer_offset = 0usize;
    let mut buffer_size = 1usize;

    for frame in 0..frame_count {
        let input_offset = frame * DEFAULT_CHROMA_BANDS;
        buffer[buffer_offset].copy_from_slice(&chroma[input_offset..input_offset + DEFAULT_CHROMA_BANDS]);
        buffer_offset = (buffer_offset + 1) % buffer.len();

        if buffer_size >= coefficients.len() {
            let offset = (buffer_offset + buffer.len() - coefficients.len()) % buffer.len();
            result.fill(0.0);
            for band in 0..DEFAULT_CHROMA_BANDS {
                for j in 0..coefficients.len() {
                    result[band] += buffer[(offset + j) % buffer.len()][band] * coefficients[j];
                }
            }
            output.extend_from_slice(&result);
        } else {
            buffer_size += 1;
        }
    }

    output
}

fn normalize_chroma_vectors(chroma: &[f64], eps: f64) -> Vec<f64> {
    if chroma.is_empty() {
        return Vec::new();
    }

    assert_eq!(chroma.len() % DEFAULT_CHROMA_BANDS, 0);
    let mut output = chroma.to_vec();
    for frame in output.chunks_exact_mut(DEFAULT_CHROMA_BANDS) {
        let norm = frame.iter().fold(0.0, |acc, x| acc + x.powi(2)).sqrt();
        if norm < eps {
            frame.fill(0.0);
        } else {
            for value in frame {
                *value /= norm;
            }
        }
    }
    output
}

fn freq_to_index(freq: u32, frame_size: usize, sample_rate: u32) -> usize {
    (frame_size as f64 * freq as f64 / sample_rate as f64).round() as usize
}

fn index_to_freq(index: usize, frame_size: usize, sample_rate: u32) -> f64 {
    index as f64 * sample_rate as f64 / frame_size as f64
}

fn freq_to_octave(freq: f64) -> f64 {
    let base = 440.0 / 16.0;
    f64::log2(freq / base)
}

fn make_hamming_window(size: usize, scale: f64) -> Vec<f64> {
    let mut window = Vec::with_capacity(size);
    if size == 1 {
        window.push(scale);
        return window;
    }

    for i in 0..size {
        window.push(
            scale
                * (0.54
                    - 0.46
                        * f64::cos(2.0 * std::f64::consts::PI * i as f64 / (size as f64 - 1.0))),
        );
    }
    window
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}
