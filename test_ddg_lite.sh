for i in {1..10}; do
  curl -s -d "q=test$i" -A "Mozilla/5.0" "https://lite.duckduckgo.com/lite/" | grep -o 'result-snippet' | wc -l
  sleep 1
done
