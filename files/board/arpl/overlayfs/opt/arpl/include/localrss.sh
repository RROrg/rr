
function mkLocalRss() {
RDPATH=${1}
MLINK=${2}
MCHECKSUM=${3}
OUTPATH=${4}

if [ ! -f ${RDPATH}/etc/VERSION ]; then
  return 1
fi

. ${RDPATH}/etc/VERSION

cat > ${OUTPATH}/localrss.json << EOF
{
  "version": "2.0",
  "channel": {
    "title": "RSS for DSM Auto Update",
    "link": "https://update.synology.com/autoupdate/v2/getList",
    "pubDate": "Sat Aug 6 0:18:39 CST 2022",
    "copyright": "Copyright 2022 Synology Inc",
    "item": [
      {
        "title": "DSM ${productversion}-${buildnumber}",
        "MajorVer": ${major},
        "MinorVer": ${minor},
        "NanoVer": ${micro},
        "BuildPhase": "${buildphase}",
        "BuildNum": ${buildnumber},
        "BuildDate": "${builddate}",
        "ReqMajorVer": ${major},
        "ReqMinorVer": ${minor},
        "ReqBuildPhase": ${micro},
        "ReqBuildNum": 0,
        "ReqBuildDate": "${builddate}",
        "isSecurityVersion": false,
        "model": [
            {
                "mUnique": "${unique}",
                "mLink": "${MLINK}",
                "mCheckSum": "${MCHECKSUM}"
            }
        ]
      }
    ]
  }
}
EOF

cat > ${OUTPATH}/localrss.xml << EOF
<?xml version="1.0"?>
<rss version="2.0">
  <channel>
      <title>RSS for DSM Auto Update</title>
      <link>http://update.synology.com/autoupdate/genRSS.php</link>
      <pubDate>Tue May 9 11:52:15 CST 2023</pubDate>
      <copyright>Copyright 2023 Synology Inc</copyright>
    <item>
      <title>DSM ${productversion}-${buildnumber}</title>
      <MajorVer>${major}</MajorVer>
      <MinorVer>${minor}</MinorVer>
      <BuildPhase>${buildphase}</BuildPhase>
      <BuildNum>${buildnumber}</BuildNum>
      <BuildDate>${builddate}</BuildDate>
      <ReqMajorVer>${major}</ReqMajorVer>
      <ReqMinorVer>${minor}</ReqMinorVer>
      <ReqBuildPhase>${micro}</ReqBuildPhase>
      <ReqBuildNum>0</ReqBuildNum>
      <ReqBuildDate>${builddate}</ReqBuildDate>
      <model>
        <mUnique>${unique}</mUnique>
        <mLink>${MLINK}</mLink>
        <mCheckSum>${MCHECKSUM}</mCheckSum>
      </model>
    </item>
  </channel>
</rss>
EOF

return 0
}
