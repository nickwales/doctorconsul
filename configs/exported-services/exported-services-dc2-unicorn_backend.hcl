Kind = "exported-services"
Partition = "unicorn"
Name = "unicorn"
Services = [
  {
    Name = "unicorn-backend"
    Namespace = "backend"
    Consumers = [
      {
        Peer = "dc1-unicorn"
      }
    ]
  }
]

