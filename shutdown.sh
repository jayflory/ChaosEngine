read -s -p "Password:  " password
for i in {1..10}; do
  echo -e "Shutting down pi$i"
  echo $password | ssh ubuntu@pi$i "sudo -S shutdown -h now"
done

echo -e "Sleeping for 25 seconds."
sleep 25
for i in {1..3}; do
  echo -e "Shutting down etcd$i"
  echo $password | ssh ubuntu@etcd$i "sudo -S shutdown -h now"
done
