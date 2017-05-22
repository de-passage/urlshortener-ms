# ###########
#   Imports #
# ###########

express = require 'express'
path = require 'path'
mongo = require('mongodb').MongoClient
body_parser = require('body-parser')

# ##############
# Declarations #
# ##############

app = express()
port = process.env.PORT
user = process.env.DB_USER
password = process.env.DB_PASSWORD
db_url = "mongodb://#{user}:#{password}@ds149501.mlab.com:49501/urlshortening"

# ###########
# Functions #
# ###########

renderErrorPage = (err, res) ->
  res.render 'index.pug', { error: err }

# Find the first available numeric alias in base 16 and pair it with the 
# provided url in the db, then callback
insertNewURL = (db, url, id, callback) ->
  alias = id.toString(16)
  urls = db.collection('urls')
  urls.find( { alias: alias } ).toArray (err, docs) ->
    if err
      return callback err
    else if docs.length > 0
      return insertNewURL db, url, id + 1, callback
    else
      urls.insert({ url: url, alias: alias })
        .then (r) ->
          console.log r
          if r.insertedCount == 1
            callback null, alias
          else
            callback { error: "Insertion failed" }

isURL = (str) ->
  str.match /^https?:\/\/([0-9a-zA-Z][-0-9a-zA-Z]+\.)+[0-9a-zA-Z][-0-9a-zA-Z]+(\/.*)?$/



# ################
# Express config #
# ################

app.set 'views', 'app/views'
app.set 'view engine', 'pug'

app.use body_parser.json()
app.use body_parser.urlencoded extended: true

# ########
# Routes #
# ########

app.use '/static', express.static '/public'

app.get "/", (req, res) ->
  error = req.query.error
  alias = req.query.alias
  url = req.query.url
  res.render 'index.pug', error: error, alias: alias, url: url

app.post "/", (req, res) ->
  url = req.body.url
  alias = req.body.alias
  return res.redirect "/?error=" + encodeURIComponent("url or alias missing") unless url and alias?
  return res.redirect "/?error=invalid url #{encodeURIComponent url}." unless isURL url
  mongo.connect db_url, (err, db) ->
    if err
      renderErrorPage JSON.stringify(err), res
    else
      db.collection('urls').insert { url: url, alias: alias }, (err) ->
        if err
          renderErrorPage err.errmsg, res
        else
          res.redirect "/?url=#{url}&alias=#{alias}"


app.get "/api/:url", (req, res) ->
  url = req.params.url
  return res.json error: "Invalid url " + url + ". Please make sure you have included a protocole (http or https only) and that the format is correct." unless isURL url
  mongo.connect db_url, (err, db) ->
    if err
      res.json err
    else
      db.collection('urls').find( $or: [ { count: { $exists: true } }, { url: url } ] ).toArray (err, docs) ->
        if err
          res.json err
        else
          id = null
          for el in docs
            if el.alias?
              return res.json alias: el.alias, original: url, url: req.headers.host + "/" + el.alias
            else if el.count?
              id = el.count
          insertNewURL db, url, id, (err, al) ->
            console.log al
            if err
              res.json err
            else
              res.json original: url, alias: al, url: req.headers.host + "/" + al


  

app.get "/:alias", (req, res) ->
  alias = req.params.alias
  mongo.connect db_url, (err, db) ->
    if err
      renderErrorPage err, res
    else
      db.collection('urls').find(alias: alias).toArray (err, docs) ->
        if err || docs.length == 0
          renderErrorPage err or "#{alias} is not a registered alias", res
        else
          res.redirect docs[0].url
          

app.listen port
