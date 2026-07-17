"""The reverse-proxy serves HTTPS with a real certificate obtained by
mwaeckerlin/letsencrypt from the local Pebble ACME test server, and switches the
domain from HTTP to HTTPS once the certificate appears (certificate watch).
"""
from conftest import DOMAIN, https_get, http_get, peer_certificate_der, wait_until

from cryptography import x509
from cryptography.x509.oid import ExtensionOID, NameOID


def _https_ok():
    r = https_get("/")
    return r if r.status_code == 200 and "BACKEND-OK" in r.text else None


def test_https_serves_backend_after_certificate_issued():
    # The certificate is issued asynchronously; the proxy's certificate watch
    # reloads nginx and HTTPS starts serving the forwarded backend.
    r = wait_until(_https_ok)
    assert r is not None, "HTTPS did not start serving the backend in time"
    assert "BACKEND-OK" in r.text


def test_http_redirects_to_https_once_secured():
    # Before the certificate exists the domain is served over plain HTTP; once
    # secured, HTTP permanently points at HTTPS. Wait for that switch.
    def redirects():
        r = http_get("/")
        loc = r.headers.get("Location", "")
        return r.status_code == 302 and loc.startswith("https://" + DOMAIN)
    assert wait_until(redirects), "HTTP did not switch to redirecting to HTTPS"


def test_https_presents_the_issued_certificate():
    # Make sure HTTPS is up first.
    assert wait_until(_https_ok) is not None
    cert = x509.load_der_x509_certificate(peer_certificate_der())
    san = cert.extensions.get_extension_for_oid(
        ExtensionOID.SUBJECT_ALTERNATIVE_NAME
    ).value.get_values_for_type(x509.DNSName)
    assert DOMAIN in san
    issuer_cn = cert.issuer.get_attributes_for_oid(NameOID.COMMON_NAME)
    assert issuer_cn and "Pebble" in issuer_cn[0].value


def test_https_sets_hsts_header():
    assert wait_until(_https_ok) is not None
    r = https_get("/")
    assert "Strict-Transport-Security" in r.headers


def test_www_over_http_redirects_to_https():
    # www must redirect to the bare host over HTTPS once the domain is secured.
    def redirects():
        r = http_get("/", headers={"Host": "www." + DOMAIN})
        loc = r.headers.get("Location", "")
        return r.status_code == 302 and loc.startswith("https://" + DOMAIN)
    assert wait_until(redirects), "www did not redirect to HTTPS"
