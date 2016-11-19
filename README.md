# ID3v2 [![Build Status](https://travis-ci.org/Cheezmeister/elixir-id3v2.svg?branch=master)](https://travis-ci.org/Cheezmeister/elixir-id3v2)
[![hex.pm version](https://img.shields.io/hexpm/v/id3v2.svg?style=flat)](https://hex.pm/packages/id3v2)

Basic ID3v2 tag parsing for Elixir. This is a work in progress. 

Be prepared to *Use the Source, Luke*. Expect bugs.

## Usage

```elixir
    contents = File.read!('track.mp3')
    tag_header = ID3v2.header(contents)
    {major, minor} = tag_header.version
    IO.puts "ID3 version 2.#{major}.#{minor}"

    tag_frames = ID3v2.frames(contents)
    IO.puts "Track title: #{tag_frames.TIT2}"
    IO.puts "Track artist: #{tag_frames.TPE1}"
    IO.puts "Track album: #{tag_frames.TALB}"
```

## Installation

The package can be installed as:

  1. Add `id3v2` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:id3v2, "~> 0.1.0"}]
    end
    ```

