defmodule ID3v2 do
  require Logger

  @moduledoc """
  # ID3v2

  Basic ID3v2 tag parsing for Elixir. This is a work in progress. 

  Be prepared to *Use the Source, Luke*. Expect bugs.
  """
  require Bitwise
  use Bitwise

  defmodule HeaderFlags do
    defstruct [:unsynchronized, :extended_header, :experimental]

    @unsynchronized_bit 128
    @extended_header_bit 64
    @experimental_bit 32

    def read(byte) do
      %HeaderFlags{
        experimental: 0 != Bitwise.band(byte, @experimental_bit),
        unsynchronized: 0 != Bitwise.band(byte, @unsynchronized_bit),
        extended_header: 0 != Bitwise.band(byte, @extended_header_bit),
      }
    end
  end

  defmodule FrameHeaderFlags do
    defstruct [
      :tag_alter_preservation,
      :file_alter_preservation,
      :read_only,
      :grouping_identity,
      :compression,
      :encryption,
      :unsynchronisation,
      :data_length_indicator,
    ]

    @tag_alter_preservation_bit (1 <<< 15)
    @file_alter_preservation_bit (1 <<< 14)
    @read_only_bit (1 <<< 13)
    @grouping_identity_bit 16
    @compression_bit 8
    @encryption_bit 4
    @unsynchronisation_bit 2
    @data_length_indicator_bit 1

    def read(<<doublebyte::integer-16>>) do
      %FrameHeaderFlags{
        tag_alter_preservation: 0 != (doublebyte &&& @tag_alter_preservation_bit),
        file_alter_preservation: 0 != (doublebyte &&& @file_alter_preservation_bit),
        read_only: 0 != (doublebyte &&& @read_only_bit),
        tag_alter_preservation: 0 != (doublebyte &&& @tag_alter_preservation_bit),
        file_alter_preservation: 0 != (doublebyte &&& @file_alter_preservation_bit),
        read_only: 0 != (doublebyte &&& @read_only_bit),
        grouping_identity: 0 != (doublebyte &&& @grouping_identity_bit),
        compression: 0 != (doublebyte &&& @compression_bit),
        encryption: 0 != (doublebyte &&& @encryption_bit),
        unsynchronisation: 0 != (doublebyte &&& @unsynchronisation_bit),
        data_length_indicator: 0 != (doublebyte &&& @data_length_indicator_bit),
      }
    end

  end

  @doc"""
  Read the main ID3 header from the file. Extended header is not read nor allowed.

  Returns `version`, `flags` and `size` in bytes, as a Map.

  `version` is a `{major, minor}` tuple.
  `flags` is a `HeaderFlags` struct, see definition. Flags are only read, not recognized nor honored.
  """
  def header(filecontents) do
    << "ID3",
    version :: binary-size(2),
    flags :: integer-8,
    size :: binary-size(4),
    _ :: binary >> = filecontents

    << versionMajor, versionMinor >> = version
    flags = read_flags(flags)
    if flags.extended_header do
      raise "This tag has an extended header. Extended header is not supported."
    end

    header = %{
      version: {versionMajor, versionMinor},
      flags: flags,
      size: unpacked_size(size) }

    header
  end

  def read_flags(byte) do
    HeaderFlags.read byte
  end

  def unpacked_size(quadbyte) do
    << byte1, byte2, byte3, byte4 >> = quadbyte
    byte4 + (byte3<<<7) + (byte2<<<14) + (byte1<<<21)
  end

  @doc"""
  Read all ID3 frames from the file.

  Returns a Map of 4-character frame ID to frame content. For example:
      
      %{
        "TIT2" => "Anesthetize"
        "TPE1" => "Porcupine Tree"
        "TALB" => "Fear of a Blank Planet"
        ...
      }
  """
  def frames(filecontent) do
    h = header(filecontent)
    headerSize = h.size
    << _header :: binary-size(10), framedata :: binary-size(headerSize), _ :: binary >> = filecontent

    _read_frames(h, :binary.copy framedata)
  end

  # Handle padding bytes at the end of the tag
  defp _read_frames(_, <<0, _ :: binary>>) do
    %{}
  end
  defp _read_frames(header, framedata) do

    << frameheader :: binary-size(10), rest :: binary >> = framedata
    << key :: binary-size(4), size :: binary-size(4), flags :: binary-size(2) >> = frameheader

    flags = FrameHeaderFlags.read flags

    pldSize = case header.version do
      {3, _} -> <<s::integer-32>> = size; s
      {4, _} -> unpacked_size size
      {v, _} -> raise "ID3v2.#{v} not supported"
    end

    << payload :: binary-size(pldSize), rest :: binary >> = rest

    # TODO handle more flags
    payload = if flags.unsynchronisation do
      p = if flags.data_length_indicator do
        <<_size::integer-32, p::binary>> = payload; p
      else
        payload
      end
      strip_zero_bytes p
    else
      payload
    end

    value = read_payload(key, payload) |> strip_zero_bytes
    # Logger.debug "#{key}: #{value}"

    Map.merge %{key => :binary.copy value}, _read_frames(header, rest)
  end

  def read_payload(key, payload) do
    << _encoding :: integer-8, _rest :: binary>> = payload

    # Special case nonsense goes here
    case key do
      "WXXX" -> read_user_url payload
      "TXXX" -> "" # TODO read_user_text payload
      "APIC" -> "" # TODO Handle embedded JPEG data?
      _ -> read_standard_payload payload
    end
  end

  defp read_standard_payload(payload) do
    << encoding :: integer-8, rest :: binary>> = payload
    # TODO Handle optional 3-byte language prefix
    case encoding do
      0 -> rest
      1 -> read_utf16 rest
      2 -> raise "I don't support utf16 without a bom"
      3 -> rest
      _ -> payload
    end
  end

  def read_user_url(payload) do
    # TODO bubble up description somehow
    {_description, link, _bom} = extract_null_terminated payload
    link
  end

	def read_user_text(payload) do
    {_description, text, bom} = extract_null_terminated payload
    case bom do
      nil -> text
      _ -> read_utf16 bom, text
    end
  end

  def extract_null_terminated(<< 1, rest::binary >>) do
    << bom :: binary-size(2), content :: binary >> = rest
    {description, value} = scan_for_null_utf16 content, []
    {description, value, bom}
  end
  def extract_null_terminated(<< encoding::integer-8, content::binary >>) do
    {description, value} = case encoding do
      0 -> scan_for_null_utf8 content, []
      3 -> scan_for_null_utf8 content, []
      _ -> raise "I don't support that text encoding (encoding was #{encoding})"
    end
    {description, value, nil}
  end

  # Based on https://elixirforum.com/t/scanning-a-bitstring-for-a-value/1852/2
  defp scan_for_null_utf16(<< c::utf16, rest::binary >>, accum) do
    case c do
      0 -> {to_string(Enum.reverse accum), rest}
      _ -> scan_for_null_utf16 rest, [c | accum]
    end
  end

  defp scan_for_null_utf8(<<c::utf8, rest::binary>>, accum) do
    case c do
      0 -> {to_string(Enum.reverse accum), rest}
      _ -> scan_for_null_utf8 rest, [c | accum]
    end
  end

  def read_utf16("") do
    ""
  end

  def read_utf16(<< bom :: binary-size(2), content :: binary >>) do
    read_utf16 bom, content
  end

  def read_utf16(bom, content) do
    {encoding, _charsize} = :unicode.bom_to_encoding(bom)
    :unicode.characters_to_binary content, encoding
  end

  def strip_zero_bytes(<<h, t::binary>>) do
    case h do
      0 -> t
      _ -> << h, strip_zero_bytes(t)::binary>>
    end
  end

  def strip_zero_bytes(<<h>>) do
    case h do
      0 -> <<>>
      _ -> h
    end
  end

  def strip_zero_bytes(<<>>) do
    <<>>
  end

end
