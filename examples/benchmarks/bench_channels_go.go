package main

func main() {
	ch := make(chan int, 1000)

	// Send 100k items (sequentially, queue-style)
	for i := 0; i < 100000; i++ {
		select {
		case ch <- i:
		default:
			// Buffer full, receive one then retry
			<-ch
			ch <- i
		}
	}

	// Receive remaining items
	close(ch)
	for range ch {
	}
}
