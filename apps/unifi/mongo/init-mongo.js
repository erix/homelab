// Initialize the "unifi" database
db = db.getSiblingDB('unifi');

// Create a user with read-write access to the "unifi" database
db.getSiblingDB("unifi").createUser({
  user: 'unifi',
  pwd: 'unifiPassword',
  roles: [{ role: 'readWrite', db: 'unifi' }]
});
db.getSiblingDB("unifi_stat").createUser({user: "unifi", pwd: "unifiPassword", roles: [{role: "dbOwner", db: "unifi_stat"}]});
