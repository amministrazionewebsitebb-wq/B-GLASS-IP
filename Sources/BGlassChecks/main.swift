import BGlassCore
import Foundation

let h = Harness()

print("BGlassCore checks")
runBasicChecks(h)
runGenresChecks(h)
runParserChecks(h)
runPacksChecks(h)
runVariantsChecks(h)
await runNetworkChecks(h)
runScaleChecks(h)

exit(h.summary())
