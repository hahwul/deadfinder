{
  chunky_png = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "89d5b31b55c0cf4da3cf89a2b4ebc3178d8abe8cbaf116a1dba95668502fdcfe";
      type = "gem";
    };
    version = "1.4.0";
  };
  colorize = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "0shj8ay8s7xbcnq4drzf9gkv7qp9qwwvlgb5drr7c27h10m06rzc";
      type = "gem";
    };
    version = "1.1.0";
  };
  concurrent-ruby = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "6b56837e1e7e5292f9864f34b69c5a2cbc75c0cf5338f1ce9903d10fa762d5ab";
      type = "gem";
    };
    version = "1.3.6";
  };
  concurrent-ruby-edge = {
    dependencies = [ "concurrent-ruby" ];
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "555c7301abf215c9e14cd3d3813e5693250daae7a4fe5448d33ba97f4472dbea";
      type = "gem";
    };
    version = "0.7.2";
  };
  date = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "750d06384d7b9c15d562c76291407d89e368dda4d4fff957eb94962d325a0dc0";
      type = "gem";
    };
    version = "3.5.1";
  };
  ethon = {
    dependencies = [ "ffi" ];
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "0gggrgkcq839mamx7a8jbnp2h7x2ykfnbzmsmrdwrvmb5vz2f5c2";
      type = "gem";
    };
    version = "0.15.0";
  };
  ffi = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "0e9f39f7bb3934f77ad6feab49662be77e87eedcdeb2a3f5c0234c2938563d4c";
      type = "gem";
    };
    version = "1.17.1";
  };
  json = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "b10506aee4183f5cf49e0efc48073d7b75843ce3782c68dbeb763351c08fd505";
      type = "gem";
    };
    version = "2.10.2";
  };
  mini_portile2 = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "0cd7c7f824e010c072e33f68bc02d85a00aeb6fce05bb4819c03dfd3c140c289";
      type = "gem";
    };
    version = "2.8.8";
  };
  nokogiri = {
    dependencies = [ "mini_portile2" "racc" ];
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "e304d21865f62518e04f2bf59f93bd3a97ca7b07e7f03952946d8e1c05f45695";
      type = "gem";
    };
    version = "1.18.8";
  };
  open-uri = {
    dependencies = [ "stringio" "time" "uri" ];
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "7b4f06fdac39e6946aed15a8da82531580882fbbec80438adcb7c30d388887ca";
      type = "gem";
    };
    version = "0.5.0";
  };
  racc = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "4a7f6929691dbec8b5209a0b373bc2614882b55fc5d2e447a21aaa691303d62f";
      type = "gem";
    };
    version = "1.8.1";
  };
  set = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "ca33a60d202e788041d94a5d4c12315b1639875576f1a266f3a10913646d8ef1";
      type = "gem";
    };
    version = "1.1.2";
  };
  sitemap-parser = {
    dependencies = [ "nokogiri" "typhoeus" ];
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "bccb0d5ff71ea1d573200e0c94b277fe7f47c83883e0c1fbb3e50bd077235439";
      type = "gem";
    };
    version = "0.5.6";
  };
  stringio = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "c37cb2e58b4ffbd33fe5cd948c05934af997b36e0b6ca6fdf43afa234cf222e1";
      type = "gem";
    };
    version = "3.2.0";
  };
  thor = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "8763e822ccb0f1d7bee88cde131b19a65606657b847cc7b7b4b82e772bcd8a3d";
      type = "gem";
    };
    version = "1.4.0";
  };
  time = {
    dependencies = [ "date" ];
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "f324e498c3bde9471d45a7d18f874c27980e9867aa5cfca61bebf52262bc3dab";
      type = "gem";
    };
    version = "0.4.2";
  };
  typhoeus = {
    dependencies = [ "ethon" ];
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "120b67ed1ef515e6c0e938176db880f15b0916f038e78ce2a66290f3f1de3e3b";
      type = "gem";
    };
    version = "1.5.0";
  };
  uri = {
    groups = [ "default" ];
    platforms = [ ];
    source = {
      remotes = [ "https://rubygems.org" ];
      sha256 = "379fa58d27ffb1387eaada68c749d1426738bd0f654d812fcc07e7568f5c57c6";
      type = "gem";
    };
    version = "1.1.1";
  };
}
