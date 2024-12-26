# -*- coding: utf-8 -*-
import os
import time
from datetime import datetime, timedelta
from pytz import timezone
from skyfield.api import load, Topos

# ISS observation settings
latitude = 55.5711   # Latitude
longitude = 24.2554  # Longitude
elevation = 0        # Elevation above sea level (meters)
local_tz = timezone("Europe/Vilnius")  # Timezone +2 hours

# SDR settings
frequency = "145.8M"  # ISS frequency
sample_rate = "240k"  # Sample rate
gain = "30"           # SDR gain

# Directories
audio_dir = "./audio/"
foto_dir = "./foto/"

# Create directories if they don't exist
os.makedirs(audio_dir, exist_ok=True)
os.makedirs(foto_dir, exist_ok=True)

def calculate_iss_passes(lat, lon, ele, duration_hours=48):
    """Calculate ISS passes for the next 48 hours."""
    ts = load.timescale()
    tle_url = "https://celestrak.com/NORAD/elements/stations.txt"
    lines = load.tle_file(tle_url)
    iss = [sat for sat in lines if sat.name == "ISS (ZARYA)"][0]

    observer = Topos(latitude_degrees=lat, longitude_degrees=lon, elevation_m=ele)
    now = ts.now()
    end_time = ts.utc(now.utc_datetime() + timedelta(hours=duration_hours))
    step_seconds = 10  # 10 seconds step

    t = now
    passes = []
    while t < end_time:
        difference = iss - observer
        topocentric = difference.at(t)
        alt, _, _ = topocentric.altaz()
        if alt.degrees > 0:
            if not passes or passes[-1][1] != t.utc_datetime():
                # Start of a new pass
                start_time = t.utc_datetime()
                max_altitude = alt.degrees
                while t < end_time:
                    t = ts.utc(t.utc_datetime() + timedelta(seconds=step_seconds))
                    difference = iss - observer
                    topocentric = difference.at(t)
                    alt, _, _ = topocentric.altaz()
                    max_altitude = max(max_altitude, alt.degrees)
                    if alt.degrees <= 0:
                        # End of the pass
                        end_time_pass = t.utc_datetime()
                        passes.append((start_time, end_time_pass, max_altitude))
                        break
        t = ts.utc(t.utc_datetime() + timedelta(seconds=step_seconds))

    return passes

def colorize_altitude(altitude):
    """Change altitude color based on its value."""
    if altitude <= 5:
        color = "\033[31m"  # Red
    elif 5 < altitude <= 15:
        color = "\033[33m"  # Yellow
    else:
        color = "\033[32m"  # Green
    return f"{color}{altitude:.2f}\033[0m"

def record_signal(start_time, end_time, output_file):
    """Record signal from start_time to end_time."""
    duration = int((end_time - start_time).total_seconds())
    print(f"Recording starts at {start_time} and ends at {end_time} ({duration} seconds)")
    command = f"rtl_fm -f {frequency} -s {sample_rate} -g {gain} - | sox -t raw -r {sample_rate} -e s -b 16 -c 1 - {output_file} trim 0 {duration}"
    os.system(command)
    print(f"Recording finished. File saved: {output_file}")

def decode_with_qsstv(input_file, output_dir=foto_dir):
    """Run QSSTV to decode SSTV images from WAV file."""
    print(f"Decoding file: {input_file}")
    command = f"qsstv --file {input_file} --output-dir {output_dir}"
    os.system(command)
    print(f"Decoding finished. Images saved to: {output_dir}")

def convert_to_local_time(utc_time):
    """Convert UTC time to local time with +2 hours offset."""
    utc_time = datetime.fromisoformat(utc_time.isoformat())
    local_time = utc_time.replace(tzinfo=timezone("UTC")).astimezone(local_tz)
    return local_time.strftime("%Y-%m-%d %H:%M:%S")

def print_separator(symbol="=", length=40):
    """Print a decorative separator line."""
    print(symbol * length)

if __name__ == "__main__":
    while True:
        print_separator("=")
        print("Calculating ISS passes for the next 48 hours...")
        print_separator("=")

        passes = calculate_iss_passes(latitude, longitude, elevation)

        if not passes:
            print("No passes found.")
            print_separator("-")
            exit()

        # Display all passes
        print_separator("#")
        print("All calculated passes (local time):")
        print_separator("#")
        for i, (rise_time, set_time, max_altitude) in enumerate(passes, start=1):
            local_rise = convert_to_local_time(rise_time)
            local_set = convert_to_local_time(set_time)
            colored_altitude = colorize_altitude(max_altitude)
            print(f"{i}. ISS will appear at {local_rise}, max elevation: {colored_altitude}, and disappear at {local_set}")

        # Process each pass
        for rise_time, set_time, _ in passes:
            print_separator("-")
            print(f"Starting ISS pass: from {convert_to_local_time(rise_time)} to {convert_to_local_time(set_time)}")
            now = load.timescale().now()

            if rise_time > now.utc_datetime():
                # Wait until ISS appears
                wait_time = (rise_time - now.utc_datetime()).total_seconds()
                print(f"Waiting {int(wait_time)} seconds until recording starts...")
                time.sleep(wait_time)

            # Create file name
            timestamp = rise_time.strftime("%Y%m%d_%H%M%S")
            wav_file = os.path.join(audio_dir, f"iss_sstv_{timestamp}.wav")

            # Start recording
            record_signal(rise_time, set_time, wav_file)

            # Automatically decode SSTV signal
            decode_with_qsstv(wav_file)

        print_separator("=")
        print("\nAll ISS passes processed. Process complete.")
        print_separator("=")

        # Wait until midnight
        now = datetime.now(local_tz)
        next_midnight = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
        sleep_time = (next_midnight - now).total_seconds()
        print(f"Waiting until midnight (00:00). Time left: {int(sleep_time)} seconds.")
        time.sleep(sleep_time)
