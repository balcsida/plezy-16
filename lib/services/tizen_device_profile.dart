/// Conservative Tizen 6 baseline, not a hardware capability probe. Widen only
/// after UE55AU7022KXXH device tests; HEVC/HDR/AV1 and passthrough are unclaimed.
Map<String, Object?> tizenDeviceProfile({bool burnSubtitles = false, int? maxStreamingBitrate}) => {
  'Name': 'Plezy Tizen 6',
  'MaxStreamingBitrate': maxStreamingBitrate ?? 20000000,
  'DirectPlayProfiles': const [
    {'Type': 'Video', 'Container': 'mp4,m4v', 'VideoCodec': 'h264', 'AudioCodec': 'aac'},
    {'Type': 'Audio', 'Container': 'mp3,aac,m4a', 'AudioCodec': 'mp3,aac'},
  ],
  'TranscodingProfiles': const [
    {
      'Type': 'Video',
      'Container': 'ts',
      'Protocol': 'hls',
      'VideoCodec': 'h264',
      'AudioCodec': 'aac',
      'MaxAudioChannels': '2',
      'Context': 'Streaming',
    },
    {
      'Type': 'Audio',
      'Container': 'mp3',
      'Protocol': 'http',
      'AudioCodec': 'mp3',
      'MaxAudioChannels': '2',
      'Context': 'Streaming',
    },
  ],
  'CodecProfiles': const [
    {
      'Type': 'Video',
      'Codec': 'h264',
      'Conditions': [
        {'Condition': 'LessThanEqual', 'Property': 'Width', 'Value': '1920', 'IsRequired': true},
        {'Condition': 'LessThanEqual', 'Property': 'Height', 'Value': '1080', 'IsRequired': true},
        {'Condition': 'LessThanEqual', 'Property': 'VideoBitDepth', 'Value': '8', 'IsRequired': true},
        {'Condition': 'LessThanEqual', 'Property': 'VideoLevel', 'Value': '41', 'IsRequired': true},
      ],
    },
    {
      'Type': 'VideoAudio',
      'Codec': 'aac',
      'Conditions': [
        {'Condition': 'LessThanEqual', 'Property': 'AudioChannels', 'Value': '2', 'IsRequired': true},
      ],
    },
  ],
  'SubtitleProfiles': [
    if (!burnSubtitles) ...const [
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'srt', 'Method': 'External'},
    ],
    // No Embed/bitmap/ASS claim. The server paints unsupported formats.
    for (final format in ['srt', 'vtt', 'ass', 'ssa', 'pgssub', 'dvdsub', 'dvbsub'])
      {'Format': format, 'Method': 'Encode'},
  ],
};
