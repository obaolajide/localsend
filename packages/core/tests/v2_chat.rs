#![cfg(feature = "http")]

use localsend::crypto::cert::generate_self_signed;
use localsend::http::client::{ClientError, LsHttpClientV2};
use localsend::http::dto_v2::ChatMessageDtoV2;
use localsend::http::server::v2::ServerEventV2;
use localsend::http::server::web::WebConfig;
use localsend::http::server::{start_with_port, ServerConfigV2, TlsConfig};
use localsend::http::state::ClientInfo;
use localsend::reqwest;
use tokio::sync::{mpsc, oneshot};

#[tokio::test]
async fn chat_uses_verified_client_identity_and_validates_body() {
    let server = generate_self_signed().unwrap();
    let sender = generate_self_signed().unwrap();
    let (event_tx, mut event_rx) = mpsc::channel(8);
    let (stop_tx, stop_rx) = oneshot::channel();
    let handle = start_with_port(
        0,
        Some(TlsConfig {
            cert: server.certificate_pem.clone(),
            private_key: server.private_key_pem.clone(),
        }),
        ClientInfo {
            alias: "Chat test".into(),
            version: "2.2".into(),
            device_model: None,
            device_type: None,
            token: server.fingerprint.clone(),
        },
        None,
        Some(ServerConfigV2 {
            pin: None,
            verify_checksums: true,
            event_tx,
        }),
        WebConfig::default(),
        stop_rx,
    )
    .await
    .unwrap();

    let client = LsHttpClientV2::try_new(
        &sender.private_key_pem,
        &sender.certificate_pem,
        Some(server.fingerprint.clone()),
        None,
    )
    .unwrap();
    client
        .chat(
            "127.0.0.1",
            handle.port(),
            ChatMessageDtoV2 {
                id: "message-1".into(),
                timestamp: "2026-10-06T10:00:00Z".into(),
                content: "hello".into(),
            },
        )
        .await
        .unwrap();
    match event_rx.recv().await.unwrap() {
        ServerEventV2::ChatReceived {
            cert_fingerprint,
            message,
            ..
        } => {
            assert_eq!(cert_fingerprint, sender.fingerprint);
            assert_eq!(message.content, "hello");
        }
        other => panic!("unexpected event: {other:?}"),
    }

    let error = client
        .chat(
            "127.0.0.1",
            handle.port(),
            ChatMessageDtoV2 {
                id: "message-2".into(),
                timestamp: "2026-10-06T10:00:00Z".into(),
                content: String::new(),
            },
        )
        .await
        .unwrap_err();
    assert!(matches!(error, ClientError::StatusCode(status) if status.status == 400));

    // The same authenticated connection must reject an oversized body.
    let identity = reqwest::Identity::from_pem(
        format!("{}{}", sender.certificate_pem, sender.private_key_pem).as_bytes(),
    )
    .unwrap();
    let raw = reqwest::Client::builder()
        .identity(identity)
        .danger_accept_invalid_certs(true)
        .no_proxy()
        .build()
        .unwrap();
    let response = raw
        .post(format!(
            "https://127.0.0.1:{}/api/localsend/v2/chat",
            handle.port()
        ))
        .body("x".repeat(16 * 1024 + 1))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status().as_u16(), 413);
    let _ = stop_tx.send(());
}

#[tokio::test]
async fn chat_rejects_unencrypted_requests() {
    let (event_tx, mut event_rx) = mpsc::channel(8);
    let (stop_tx, stop_rx) = oneshot::channel();
    let handle = start_with_port(
        0,
        None,
        ClientInfo {
            alias: "Chat test".into(),
            version: "2.2".into(),
            device_model: None,
            device_type: None,
            token: "plain-test".into(),
        },
        None,
        Some(ServerConfigV2 {
            pin: None,
            verify_checksums: true,
            event_tx,
        }),
        WebConfig::default(),
        stop_rx,
    )
    .await
    .unwrap();
    let response = reqwest::Client::new()
        .post(format!(
            "http://127.0.0.1:{}/api/localsend/v2/chat",
            handle.port()
        ))
        .json(&ChatMessageDtoV2 {
            id: "message-1".into(),
            timestamp: "2026-10-06T10:00:00Z".into(),
            content: "hello".into(),
        })
        .send()
        .await
        .unwrap();
    assert_eq!(response.status().as_u16(), 403);
    assert!(event_rx.try_recv().is_err());
    let _ = stop_tx.send(());
}
