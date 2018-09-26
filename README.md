# 500px Image Downloader

[Ruby](https://www.ruby-lang.org) script to download images from [500px](https://500px.com).

Downloaded images are intended for personal usage as reference material. Copyright remains with the original content creator. This project does not condone or encourage copyright infringement.


## Installation

Using [rbenv](https://github.com/rbenv/rbenv) will ensure that the correct Ruby version is loaded. Ruby dependencies are managed using [Bundler](https://bundler.io).

Install Ruby dependencies:

```sh
bundle install
```


## Usage

Download a single image (`URL`) as follows:

```sh
ruby downloader.rb URL
```

Download multiple images (`URL1`, `URL2` and `URL3`) as follows:

```sh
ruby downloader.rb URL1 URL2 URL3
```

Downloaded images will be saved in the `output` directory.
