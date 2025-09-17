# Adding TLS Secrets

## Adding TLS Certificate

Kubernetes will create all the objects and services for MMAI, but it will not become available until we populate the `tls-mmai-ingress` secret in the `cattle-system` namespace with the certificate and key.

Combine the server certificate followed by any intermediate certificate(s) needed into a file named `tls.crt`. Copy your certificate key into a file named `tls.key`.

For example, `acme.sh` provides server certificate and CA chains in `fullchain.cer` file. This `fullchain.cer` should be renamed to `tls.crt` & certificate key file as `tls.key`.

Use `kubectl` with the `tls` secret type to create the secrets.

```sh
kubectl -n cattle-system create secret tls tls-mmai-ingress --cert=tls.crt --key=tls.key
```

NOTE
> If you want to replace the certificate, you can delete the `tls-mmai-ingress` secret using `kubectl -n cattle-system delete secret tls-mmai-ingress` and add a new one using the command shown above. If you are using a private CA signed certificate, replacing the certificate is only possible if the new certificate is signed by the same CA as the certificate currently in use.

## Using a Private CA Signed Certificate

If you are using a private CA, MMAI requires a copy of the private CA's root certificate or certificate chain, which the MMAI Agent uses to validate the connection to the server.

Create a file named `cacerts.pem` that only contains the root CA certificate or certificate chain from your private CA, and use `kubectl` to create the `tls-ca` secret in the `cattle-system` namespace.

```sh
kubectl -n cattle-system create secret generic tls-ca --from-file=cacerts.pem
```

NOTE
> The configured `tls-ca` secret is retrieved when MMAI starts. On a running MMAI installation the updated CA will take effect after new MMAI pods are started.
