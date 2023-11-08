{ sources ? import ./nix/sources.nix
, pkgs ? import sources.nixpkgs {
    overlays = [ ];
    config = { };
  }
}:

with pkgs;
let
  locales = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    LOCALE_ARCHIVE = if pkgs.system == "x86_64-linux"
                     then "${pkgs.glibcLocales}/lib/locale/locale-archive"
                     else "";
  };

  customAgda = import sources.agda-nixpkgs {
    inherit (pkgs) system;
  };

  agdaStdlib = customAgda.agdaPackages.standard-library.overrideAttrs (oldAttrs: {
    version = "2.0-rc1";
    src = fetchFromGitHub {
      repo = "agda-stdlib";
      owner = "agda";
      rev = "a7d23029ac94ba446d2cf2a6f4bf3859d7aa9506";
      sha256 = "tGY7FEcKKW2jSuzniAJpNGxLiL/RRzsOvrajZgKqzRc=";
    };
  });

  agdaStdlibMeta = customAgda.agdaPackages.mkDerivation {
    inherit (locales) LANG LC_ALL LOCALE_ARCHIVE;
    pname = "agda-stdlib-meta";
    version = "0.1";
    src = fetchFromGitHub {
      repo = "stdlib-meta";
      owner = "input-output-hk";
      rev = "8ccdb763214e50e830a271b1e5ff57e429c3607b";
      sha256 = "p5fNQzosNhgOR39ZVm9kwvzp6hB2563F1NSRlZSCoWo=";
    };
    meta = { };
    libraryFile = "stdlib-meta.agda-lib";
    everythingFile = "Main.agda";
    buildInputs = [ agdaStdlib ];
  };

  deps = [ agdaStdlib agdaStdlibMeta ];
  agdaWithPkgs = p: customAgda.agda.withPackages { pkgs = p; ghc = pkgs.ghc; };

in
rec {

  agdaWithStdLibMeta = agdaWithPkgs deps;
  agda = agdaWithPkgs (deps ++ [ formalLedger ]);

  latex = texlive.combine {
    inherit (texlive)
      scheme-small
      xits
      collection-latexextra
      collection-latexrecommended
      collection-mathscience
      bclogo
      latexmk;
  };

  formalLedger = customAgda.agdaPackages.mkDerivation {
    inherit (locales) LANG LC_ALL LOCALE_ARCHIVE;
    pname = "formal-ledger";
    version = "0.1";
    src = ./src;
    meta = { };
    buildInputs = deps;
    postInstall = ''
      cp -r latex/ Makefile $out
      sh checkTypeChecked.sh
      '';
    extraExtensions = [ "hs" "cabal" ];
  };

  mkSpecDerivation = { project, main }: rec {
    docs = stdenv.mkDerivation {
      inherit (locales) LANG LC_ALL LOCALE_ARCHIVE;
      pname = "docs";
      version = "0.1";
      src = "${formalLedger}";
      meta = { };
      buildInputs = [ agdaWithStdLibMeta latex ];
      buildPhase = ''
        OUT_DIR=$out make "${project}".docs
      '';
      doCheck = true;
      checkPhase = ''
        test -n "$(find $out/pdfs/ -type f -name '*.pdf')"
      '';
      dontInstall = true;
    };

    html = stdenv.mkDerivation {
      inherit (locales) LANG LC_ALL LOCALE_ARCHIVE;
      pname = "html";
      version = "0.1";
      src = "${formalLedger}";
      meta = { };
      buildInputs = [ agdaWithStdLibMeta ];
      buildPhase = ''
        OUT_DIR=$out make "${project}".html
      '';
      doCheck = true;
      checkPhase = ''
        test -n "$(find $out/html/ -type f -name '*.html')"
      '';
      dontInstall = true;
    };

    hsSrc = stdenv.mkDerivation {
      inherit (locales) LANG LC_ALL LOCALE_ARCHIVE;
      pname = "hs-src";
      version = "0.1";
      src = "${formalLedger}";
      meta = { };
      buildInputs = [ agdaWithStdLibMeta ];
      buildPhase = ''
        OUT_DIR=$out make "${project}".hs
      '';
      doCheck = true;
      checkPhase = ''
        test -n "$(find $out/haskell/ -type f -name '*.hs')"
        # OUT_DIR=$out make "${project}".hsTest
      '';
      dontInstall = true;
    };

    # hsDocs = stdenv.mkDerivation {
    #   pname = "hs-docs";
    #   version = "0.1";
    #   src = "${formalLedger}";
    #   meta = { };
    #   buildInputs = [ agdaWithStdLibMeta ];
    #   configurePhase = ''
    #     export HOME=$TMP
    #   '';
    #   buildPhase = ''
    #     OUT_DIR=$out make "${project}".hsDocs
    #   '';
    #   doCheck = true;
    #   checkPhase = ''
    #     test -n "$(find $out/haskell/ -type f -name '*.html')"
    #   '';
    #   dontInstall = true;
    # };

    hsExe = haskellPackages.callCabal2nix "${project}" "${hsSrc}/haskell/${main}" { };

  };

  ledger = mkSpecDerivation {
    project = "ledger";
    main = "Ledger";
  };
  midnight = mkSpecDerivation {
    project = "midnight";
    main = "MidnightExample";
  };
}
