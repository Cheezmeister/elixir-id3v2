defmodule ID3v2Test do
  use ExUnit.Case

	@testfile "test/fixtures/Sonic_the_Hedgehog_3_LatinSphere_OC_ReMix.mp3"

  test "header extraction" do
    file = File.read!(@testfile)
    header = ID3v2.header(file)
    assert header.version == {4, 0}
    assert header.flags.unsynchronized
    assert header.size == 72888
  end

  test "header unsynchronized flag" do
    assert ID3v2.read_flags(128).unsynchronized
  end

  test "header extended_header flag" do
    assert ID3v2.read_flags(64).extended_header
  end

  test "header experimental flag" do
    assert ID3v2.read_flags(32).experimental
  end

  test "header size extraction" do
    assert ID3v2.unpacked_size(<< 0, 4, 62, 25 >>) == 25 + (62*128) + (4*128*128) + (0)
  end

  test "read UTF-16" do
    assert "A0" == ID3v2.read_utf16 << 255, 254, 65, 00, 48, 00 >>
  end

  test "read payload ASCII/ISO-8859-1" do
    assert "pants" == ID3v2.read_payload "XXXX", << 0, "pants" :: utf8 >>
  end

  test "read payload UTF-16" do
    assert "pants" == ID3v2.read_payload "XXXX", << 1, 255, 254, "pants" :: utf16-little >>
    assert "pants" == ID3v2.read_payload "XXXX", << 1, 254, 255, "pants" :: utf16-big >>
  end

  test "read payload UTF-8" do
    assert "pants" == ID3v2.read_payload("XXXX", << 3, "pants" :: utf8 >>)
  end

  test "extract null-terminated ascii" do
    {description, rest, bom} = ID3v2.extract_null_terminated << 3, "Wat", 00, "ABC" >>
    assert description == "Wat"
    assert rest == "ABC"
    assert bom == nil
  end

  test "extract null-terminated utf8" do
    {description, rest, bom} = ID3v2.extract_null_terminated << 3, "Wat", 00, "合"::utf8 >>
    assert description == "Wat"
    assert rest == "合"
    assert bom == nil
  end

  test "extract null-terminated utf16" do
    {description, rest, bom} = ID3v2.extract_null_terminated << 1, 255, 254, "Wat"::utf16, 00, 00, 65, 66, 67 >>
    assert description == "Wat"
    assert rest == "ABC"
    assert bom == <<255, 254>>
  end

  test "read user url" do
    link = ID3v2.read_user_url << 1, 255, 254, "Desc"::utf16-little, 00, 00, "http://bogus.url" >>
    assert link == "http://bogus.url"
  end

  test "read user text" do
    text = ID3v2.read_user_text << 1, 255, 254, "Desc"::utf16-little, 00, 00, "Value"::utf16-little >>
    assert text == "Value"
  end

  test "read user text utf8" do
    text = ID3v2.read_user_text << 3, "Desc", 00, "Value" >>
    assert text == "Value"
  end

  test "strip zero bytes" do
    assert ID3v2.strip_zero_bytes(<<0>>) == <<>>
    assert ID3v2.strip_zero_bytes(<<>>) == <<>>
  end

  test "strip zero bytes complex" do
    assert ID3v2.strip_zero_bytes(<<0, 255>>) == <<255>>
    assert ID3v2.strip_zero_bytes(<<255, 0>>) == <<255>>
    assert ID3v2.strip_zero_bytes(<<255, 255>>) == <<255, 255>>
    assert ID3v2.strip_zero_bytes(<<255, 0, 255>>) == <<255, 255>>
    assert ID3v2.strip_zero_bytes(<<0, 255, 255>>) == <<255, 255>>
    assert ID3v2.strip_zero_bytes(<< 255, 255, 0 >>) == <<255, 255>>
  end

  Path.wildcard("test/fixtures/*.mp3") |> Enum.map(fn(file) ->
    @thisfile file
    test "frame data - #{Path.basename file}" do
      frames = ID3v2.frames(File.read!(@thisfile))
      assert frames["TPUB"] == "OverClocked ReMix"
    end
  end)

end
