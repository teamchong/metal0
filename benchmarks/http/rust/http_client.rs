use std::io::{Read, Write};
use std::net::TcpStream;

fn main() {
    let mut success = 0;

    for _ in 0..100 {
        // Note: This is a simplified HTTP client without SSL
        // For fair comparison, we'd need to use reqwest with rustls
        // which adds significant dependencies
        if let Ok(mut stream) = TcpStream::connect("httpbin.org:80") {
            let request = "GET /get HTTP/1.1\r\nHost: httpbin.org\r\nConnection: close\r\n\r\n";
            if stream.write_all(request.as_bytes()).is_ok() {
                let mut response = String::new();
                if stream.read_to_string(&mut response).is_ok() && response.contains("200 OK") {
                    success += 1;
                }
            }
        }
    }

    println!("{}", success);
}
