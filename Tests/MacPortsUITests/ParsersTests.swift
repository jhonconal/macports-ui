import Testing
@testable import MacPortsUICore

/// Parser tests built from real captured `port` output (MacPorts 2.12.6).
@Suite struct ParsersTests {

    // MARK: installed

    @Test func parsesInstalledLines() {
        let text = """
        The following ports are currently installed:
          android-platform-tools @36.0.2_0 (active)
          curl @8.22.0_0+brotli+http2+idn+psl+ssl+zstd (active)
          bison @3.8.2_2 (inactive)
        """
        let parsed = PortOutputParser.parseInstalled(text)
        #expect(parsed.count == 3)
        #expect(parsed[0].name == "android-platform-tools")
        #expect(parsed[0].version == "36.0.2_0")
        #expect(parsed[0].variants.isEmpty)
        #expect(parsed[1].name == "curl")
        #expect(parsed[1].version == "8.22.0_0")
        #expect(parsed[1].variants == ["brotli", "http2", "idn", "psl", "ssl", "zstd"])
        #expect(parsed[1].isActive)
        #expect(parsed[2].state == "inactive")
        #expect(parsed[2].isActive == false)
    }

    @Test func parsesInstalledQuiet() {
        // `port installed -q` has no header line.
        let text = "  assimp @5.4.3_0 (active)\n"
        let parsed = PortOutputParser.parseInstalled(text)
        #expect(parsed.count == 1)
        #expect(parsed[0].name == "assimp")
    }

    // MARK: outdated

    @Test func parsesOutdated() {
        let text = """
        The following ports are outdated:
          sqlite3 @3.44.0_0 (available: 3.45.0_0)
          openssl @3.0.9_1 (available: 3.0.13_0)
        """
        let parsed = PortOutputParser.parseOutdated(text)
        #expect(parsed.count == 2)
        #expect(parsed[0].name == "sqlite3")
        #expect(parsed[0].installedVersion == "3.44.0_0")
        #expect(parsed[0].availableVersion == "3.45.0_0")
    }

    @Test func parsesOutdatedNone() {
        #expect(PortOutputParser.parseOutdated("No installed ports are outdated.").isEmpty)
    }

    // MARK: search

    @Test func parsesSearch() {
        let text = """
        coeurl @0.3.0_1 (net, www)
        Simple library to do http requests asynchronously via CURL in C++

        cpr @1.11.1 (devel, net)
        C++ Requests: Curl for People

        curl @8.22.0 (net, www)
        Tool for transferring files with URL syntax

        curl-ca-bundle @8.22.0 (net)

        """
        let parsed = PortOutputParser.parseSearch(text)
        #expect(parsed.count == 4)
        #expect(parsed[0].name == "coeurl")
        #expect(parsed[0].categories == ["net", "www"])
        #expect(parsed[0].summary == "Simple library to do http requests asynchronously via CURL in C++")
        #expect(parsed[2].name == "curl")
        #expect(parsed[2].version == "8.22.0")
        #expect(parsed[3].name == "curl-ca-bundle")
        #expect(parsed[3].summary.isEmpty) // no description line
    }

    // MARK: info

    @Test func parsesInfo() throws {
        let text = """
        curl @8.22.0 (net, www)
        Sub-ports:            curl-ca-bundle
        Variants:             ares, [+]brotli, darwinssl, gnutls, gsasl, gss, [+]http2, http3, [+]idn, mbedtls, openldap, [+]psl, sectrust, sftp_scp, [+]ssl, universal, wolfssl, [+]zstd

        Description:          curl is a client to get documents/files from servers.
        Homepage:             https://curl.se

        Extract Dependencies: xz
        Build Dependencies:   pkgconfig
        Library Dependencies: zlib, brotli, nghttp2, libidn2, libpsl, openssl, curl-ca-bundle, zstd
        Platforms:            darwin, freebsd
        License:              Curl
        Maintainers:          Email: ryandesign@macports.org
        """
        let d = try #require(PortOutputParser.parseInfo(text))
        #expect(d.name == "curl")
        #expect(d.version == "8.22.0")
        #expect(d.categories == ["net", "www"])
        #expect(d.homepage == "https://curl.se")
        #expect(d.subports == ["curl-ca-bundle"])
        #expect(d.variantsEnabled == ["brotli", "http2", "idn", "psl", "ssl", "zstd"])
        #expect(d.variantsAll.count == 18)
        #expect(d.extractDeps == ["xz"])
        #expect(d.buildDeps == ["pkgconfig"])
        #expect(d.libraryDeps.contains("zlib"))
        #expect(d.summary.contains("client to get documents"))
    }

    @Test func variantBaseStripsMarker() {
        #expect(PortOutputParser.variantBase("[+]ssl") == "ssl")
        #expect(PortOutputParser.variantBase("universal") == "universal")
    }
}
