# Test socket module
import socket

# Test gethostname
hostname = socket.gethostname()
print("Hostname:", hostname)

# Test byte order conversion functions
port = 8080
net_port = socket.htons(port)
print("htons(8080):", net_port)

host_port = socket.ntohs(net_port)
print("ntohs back:", host_port)

# Test inet_aton/ntoa
ip = "192.168.1.1"
ip_bytes = socket.inet_aton(ip)
print("inet_aton:", len(ip_bytes), "bytes")

unpacked_ip = socket.inet_ntoa(ip_bytes)
print("inet_ntoa:", unpacked_ip)

# Test htonl/ntohl
val = 0x12345678
net_val = socket.htonl(val)
print("htonl:", net_val)

host_val = socket.ntohl(net_val)
print("ntohl:", host_val)
