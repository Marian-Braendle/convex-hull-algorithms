label = "Convex Hull"
about = [[
Draw convex hull of a set of points using different algorithms.

By Marian Braendle
]]


type = _G.type

local COLOR_PALETTE = {
    { r = 228 / 255, g =  26 / 255, b =  28 / 255 },
    { r =  55 / 255, g = 126 / 255, b = 184 / 255 },
    { r =  77 / 255, g = 175 / 255, b =  74 / 255 },
    { r = 152 / 255, g =  78 / 255, b = 163 / 255 },
    { r = 255 / 255, g = 127 / 255, b =   0 / 255 },
    { r = 166 / 255, g =  86 / 255, b =  40 / 255 },
    { r = 247 / 255, g = 129 / 255, b = 191 / 255 },
    { r = 153 / 255, g = 153 / 255, b = 153 / 255 },
}

local STYLE = {
    currentMark  = { symbolsize = 5.0, stroke = COLOR_PALETTE[6], markShape = "mark/disk(sx)" },
    checkingMark = { symbolsize = 4.0, stroke = COLOR_PALETTE[5], markShape = "mark/disk(sx)" },
    hullMark     = { symbolsize = 5.0, stroke = COLOR_PALETTE[3], markShape = "mark/disk(sx)" },
    remMark      = { symbolsize = 6.0, stroke = COLOR_PALETTE[1], markShape = "mark/cross(sx)" },
    helpMark     = { symbolsize = 3.0, stroke = COLOR_PALETTE[8], markShape = "mark/disk(sx)" },
    group1Mark   = { symbolsize = 6.0, stroke = COLOR_PALETTE[2], markShape = "mark/box(sx)" },
    group2Mark   = { symbolsize = 6.0, stroke = COLOR_PALETTE[7], markShape = "mark/circle(sx)" },

    checkingSegment = { pen = 1.5, stroke = COLOR_PALETTE[5] },
    hullSegment     = { pen = 2.0, stroke = COLOR_PALETTE[3] },
    subHullSegment  = { pen = 1.0, stroke = COLOR_PALETTE[3] },
    remSegment      = { pen = 2.0, stroke = COLOR_PALETTE[1] },
    helpSegment     = { pen = 0.5, stroke = COLOR_PALETTE[8] },

    checkingArc = { pathmode = "filled", fill = COLOR_PALETTE[5], opacity = "50%"},
}

------------------ Helper Functions ------------------
local function dump(t, max_level, cur_level)
    local INDENT = 2
    max_level = max_level or 10
    cur_level = cur_level or 1
    if type(t) == "table" and cur_level <= max_level then
        local s = "{\n"
        for k, v in pairs(t) do
            if type(k) ~= "number" then k = "\"" .. k .. "\"" end
            s = s ..  string.rep(" ", cur_level * INDENT) .. "[" .. k .. "] = " .. dump(v, max_level, cur_level + 1) .. ",\n"
        end
        return s .. string.rep(" ", (cur_level - 1) * INDENT) .. "}"
    else
        if type(t) == "userdata" and t["__name"] == "Ipe.vector" then
            return string.format("x = %.17g, y = %.17g", t.x, t.y) -- high precision for vectors
        else
            return tostring(t)
        end
    end
end

local function cloneTable(tab)
    if type(tab) ~= "table" then return tab end
    local cloned = {}
    for k, v in pairs(tab) do
        cloned[cloneTable(k)] = cloneTable(v)
    end
    return _G.setmetatable(cloned, _G.getmetatable(tab))
end

local function shuffleTable(tab) -- Fisher-Yates
  for i = #tab, 2, -1 do
    local j = math.random(i)
    tab[i], tab[j] = tab[j], tab[i]
  end
end

local function getLeftmostPoint(points)
    local res = points[1]
    for _, pt in ipairs(points) do
        if pt.x == res.x and pt.y > res.y or pt.x < res.x then
            res = pt
        end
    end
    return res
end

local function getLowerLeftPoint(points)
    local res, iRes = points[1], 0
    for i, pt in ipairs(points) do
        if pt.y == res.y and pt.x < res.x or pt.y < res.y then
            res, iRes = pt, i
        end
    end
    return res, iRes
end

local function getHorizontalExtrema(points)
    local left, right = points[1], points[1]
    for i = 2, #points do
        if points[i].x < left.x then
            left = points[i]
        end
        if points[i].x > right.x then
            right = points[i]
        end
    end
    return left, right
end

local function orientation(p1, p2, p3)
    -- z-component of p1p2 x p1p3 (extended to 3 dimensions by setting z-components to 0)
    return ((p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x))
end

--- Partition points into groups of specified size
local function partitionByGroupSize(points, groupSize)
    local groups = {}
    for i = 1, #points, groupSize do
        local group = {}
        for j = i, math.min(i + groupSize - 1, #points) do
            group[#group + 1] = points[j]
        end
        groups[#groups + 1] = group
    end
    return groups
end

---Partition points into two sets separated by line through p1 and p2
local function partitionByLine(points, p1, p2, ignoreColinearPoints)
    ignoreColinearPoints = ignoreColinearPoints or false
    local s1, s2 = {}, {}
    for _, p in ipairs(points) do
        if p ~= p1 and p ~= p2 then
            local o = orientation(p1, p2, p)
            if o > 0 then
                s1[#s1 + 1] = p
            elseif o < 0 or not ignoreColinearPoints then
                s2[#s2 + 1] = p
            end
        end
    end
    return s1, s2
end

---Get point furthest away from line pq
local function furthestPointFromLine(points, p, q)
    local pq = ipe.Segment(p, q)
    local maxDist, maxIdx = 0, 1
    for i = 1, #points do
        local dist = pq:distance(points[i])
        if dist > maxDist then
            maxDist = dist
            maxIdx = i
        end
    end
    return points[maxIdx]
end

local function removeDuplicatePoints(points)
    if #points <= 1 then return points end
    local res = {}
    table.sort(points, function(a, b) return a.x == b.x and a.y < b.y or a.x < b.x end)
    for i = 1, #points do
        if  points[i] ~= points[i % #points + 1] then res[#res+1] = points[i] end
    end
    return res
end

local function collectPoints(model)
    local p = model:page()
    local points = {}
    for _i, obj, sel, _layer in p:objects() do
        if sel then
            if obj:type() ~= "reference" then model:warning("Please select only marks!", dump(obj:shape())) return end
            points[#points + 1] = obj:matrix() * obj:position()
        end
    end
    if #points < 3 then model:warning("Please select at least three marks!") return end
    return points
end

--------------------- View Class ---------------------
View = {}
function View:new(model, name)
    local obj = _G.setmetatable({}, self)
    self.__index = self
    obj.objects = {}
    obj.model, obj.name = model, name
    return obj
end

function View:addMarks(points, attrs)
    for _, p in ipairs(points) do self.objects[#self.objects+1] = ipe.Reference(attrs, attrs.markShape, p) end
    return self
end

function View:addPolygon(points, attrs, closed)
    local shape = { type = "curve", closed = closed or false }
    if #points > 1 then
        for i = 2, #points do shape[#shape + 1] = { type = "segment", points[i - 1], points[i] } end
        self.objects[#self.objects + 1] = ipe.Path(attrs, { shape })
    end
    return self
end
function View:addAngle(p1, p2, p3, radius, attrs)
    local a, b = (p2 - p1):angle(), (p3 - p1):angle()
    local v1, v2 = p1 + radius * ipe.Direction(a), p1 + radius * ipe.Direction(b)
    local arc = ipe.Arc(ipe.Matrix(radius, 0, 0, -radius, p1.x, p1.y), a, b)
    local shape = { type = "curve", closed = false,
        { type = "arc", v1, v2, arc = arc }, { type = "segment", v2, p1 }, { type = "segment", p1, v1 }}
    self.objects[#self.objects + 1] = ipe.Path(attrs, { shape })
    return self
end

---------------- Visualization Class -----------------
Visualization = {}
function Visualization:new(model, namePrefix)
    local obj = _G.setmetatable({}, self)
    self.__index = self
    obj.views = {}
    obj.model, obj.namePrefix = model, namePrefix or "view"
    return obj
end

function Visualization:newView(name)
    name = name or (self.namePrefix .. #self.views + 1)
    self.views[#self.views+1] = View:new(self.model, name)
    return self.views[#self.views]
end

function Visualization:cloneView(existingView, name)
    existingView = existingView or (#self.views > 0 and self.views[#self.views]) or nil
    name = name or (self.namePrefix .. #self.views + 1)
    local newView = View:new(self.model, name)
    if existingView ~= nil then newView.objects = cloneTable(existingView.objects) end
    self.views[#self.views + 1] = newView
    return newView
end

function Visualization:generateIpeViews()
    local t = {
        label = "create visualization",
        pno = self.model.pno,
        vno = self.model.vno,
        vtotal = self.model:page():countViews(),
        original = self.model:page():clone(),
        undo = _G.revertOriginal
    }
    t.redo = function(t, doc)
        local page = doc[t.pno]
        for i, view in ipairs(self.views) do
            local curView = t.vtotal + i
            page:insertView(curView, page:active(t.vno))
            page:setViewName(curView, view.name)
            for _, layer in ipairs(page:layers()) do
                page:setVisible(curView, layer, page:visible(t.vno, layer))
            end
            local newLayer = page:addLayer(view.name)
            page:setVisible(curView, newLayer, true)
            for _, obj in ipairs(view.objects) do
                page:insert(nil, obj, 0, newLayer)
            end
        end
    end
    self.model:register(t)
    self.model:setPage()
end

--------------------- Algorithms ---------------------
local function bruteForce(model, points)
    local vis = Visualization:new(model, "bruteForce_")
    local hullSegments = {} -- Needed for visualization
    local iHull = {} -- hull as hash set
    for i = 1, #points do
        for j = i+1, #points do
            local s1, s2 = partitionByLine(points, points[i], points[j], true) -- O(n)
            local view = vis:newView()
            for _, s in ipairs(hullSegments) do view:addPolygon(s, STYLE.subHullSegment) end
            for k, _ in pairs(iHull) do view:addMarks({points[k]}, STYLE.hullMark) end
            view:addPolygon({points[i], points[j]}, STYLE.checkingSegment)
                :addMarks({points[i]}, STYLE.currentMark)
                :addMarks({points[j]}, STYLE.checkingMark)
                :addMarks(s1, STYLE.group1Mark)
                :addMarks(s2, STYLE.group2Mark)

            if #s1 == 0 or #s2 == 0 then
                hullSegments[#hullSegments+1] = { points[i], points[j] }
                iHull[i], iHull[j] = true, true -- Add to set
            end
        end
    end
    local view = vis:newView("bruteForce_result")
    for _, s in ipairs(hullSegments) do view:addPolygon(s, STYLE.hullSegment) end
    for k, _ in pairs(iHull) do view:addMarks({points[k]}, STYLE.hullMark) end

    local hull = {}
    for k, _ in pairs(iHull) do
        hull[#hull+1] = points[k]
    end
    return hull, vis
end

local function grahamScan(model, points)
    local vis = Visualization:new(model, "grahamScan_")
    local P = getLowerLeftPoint(points)
    -- Sort points by angle and distance to P
    table.sort(points, function(a, b)
        local dirA, dirB = a - P, b - P
        local angA, angB = dirA:angle(), dirB:angle()
        local lenA, lenB = dirA:sqLen(), dirB:sqLen()
        return angA == angB and lenA < lenB or angA < angB
    end)
    -- Collect points on convex hull
    local hull_stack = {}
    for i = 1, #points do
        while #hull_stack >= 2 and orientation(hull_stack[#hull_stack - 1], hull_stack[#hull_stack], points[i]) <= 0 do
            local rem = table.remove(hull_stack) -- pop
            vis:newView()
               :addPolygon({rem, points[i]}, STYLE.checkingSegment)
               :addPolygon(hull_stack, STYLE.subHullSegment)
               :addPolygon({hull_stack[#hull_stack], rem}, STYLE.remSegment)
               :addMarks({points[i]}, STYLE.checkingMark)
               :addMarks(hull_stack, STYLE.hullMark)
               :addMarks({rem}, STYLE.remMark)
        end
        local view = vis:newView()
        view:addPolygon(hull_stack, STYLE.subHullSegment)
        if #hull_stack > 0 then view:addPolygon({hull_stack[#hull_stack], points[i]}, STYLE.checkingSegment) end
        view:addMarks({points[i]}, STYLE.checkingMark)
        view:addMarks(hull_stack, STYLE.hullMark)

        hull_stack[#hull_stack + 1] = points[i]
        vis:newView()
           :addPolygon(hull_stack, STYLE.subHullSegment)
           :addMarks(hull_stack, STYLE.hullMark)
    end
    vis:newView("grahamScan_result")
       :addPolygon(hull_stack, STYLE.hullSegment, true)
       :addMarks(hull_stack, STYLE.hullMark)
    return hull_stack, vis
end

-- FIXME: 0° angles
local function jarvisMarch(model, points)
    local vis = Visualization:new(model, "jarvisMarch_")
    local hull, next = {}, getLeftmostPoint(points)
    -- Collect points on convex hull
    while next ~= hull[1] do
        hull[#hull + 1] = next
        local current = next
        next = points[1]
        for i = 2, #points do
            local checking = points[i]
            if checking ~= current then
                local turn = orientation(current, next, checking)
                -- Find the point with the biggest left turn. If 2 points are colinear, use the one furthest away.
                if turn > 0 or (turn == 0 and (checking - current):sqLen() > (next - current):sqLen()) then
                    next = checking
                end
                local view = vis:newView()
                if #hull > 1 then view:addAngle(current, hull[#hull - 1], checking, 10, STYLE.checkingArc) end
                view:addPolygon(hull, STYLE.subHullSegment)
                    :addPolygon({current, checking}, STYLE.checkingSegment)
                    :addMarks(hull, STYLE.hullMark)
                    :addMarks({current}, STYLE.currentMark)
                    :addMarks({checking}, STYLE.checkingMark)
            end
        end
    end
    vis:newView("jarvisMarch_result")
       :addMarks(hull, STYLE.hullMark)
       :addPolygon(hull, STYLE.hullSegment, true)
    return hull, vis
end

local function quickHull(model, points)
    local vis = Visualization:new(model, "quickHull_")
    local visTriangleStack = {}
    local hull = {} -- Modified by findHull()
    local function findHull(sk, p, q)
        if #sk == 0 then return end -- Base case
        local c = furthestPointFromLine(sk, p, q)
        local outside, inside = partitionByLine(sk, p, c)

        visTriangleStack[#visTriangleStack+1] = {p, c, q}
        local view = vis:newView()
           :addMarks(hull, STYLE.hullMark)
           :addPolygon(hull, STYLE.subHullSegment)
           :addMarks({p, c, q}, STYLE.helpMark)
        for _, t in ipairs(visTriangleStack) do view:addPolygon(t, STYLE.helpSegment, true) end
        vis:cloneView()
           :addPolygon({p, c}, STYLE.checkingSegment)
           :addMarks({p, c}, STYLE.checkingMark)
           :addMarks(inside, STYLE.group1Mark)
           :addMarks(outside, STYLE.group2Mark)

        findHull(outside, p, c) -- Visit points outside the line through p and c
        hull[#hull+1] = c -- Point furthest away from the line is part of the convex hull

        local outside2, inside2 = partitionByLine(sk, c, q)

        view = vis:newView()
           :addMarks(hull, STYLE.hullMark)
           :addPolygon(hull, STYLE.subHullSegment)
           :addMarks({q, c, p}, STYLE.helpMark)
        for _, t in ipairs(visTriangleStack) do view:addPolygon(t, STYLE.helpSegment, true) end
        vis:cloneView()
           :addPolygon({c, q}, STYLE.checkingSegment)
           :addMarks({c, q}, STYLE.checkingMark)
           :addMarks(inside2, STYLE.group1Mark)
           :addMarks(outside2, STYLE.group2Mark)

        findHull(outside2, c, q) -- Visit points outside the line through c and q
        table.remove(visTriangleStack) -- pop
    end
    local l, r = getHorizontalExtrema(points)
    local s1, s2 = partitionByLine(points, l, r) -- Partition into 2 sets separated by line through l and r
    hull[#hull+1] = l
    findHull(s1, l, r)
    hull[#hull+1] = r
    findHull(s2, r, l)

    vis:newView("quickHull_result")
       :addMarks(hull, STYLE.hullMark)
       :addPolygon(hull, STYLE.hullSegment, true)
    return hull, vis
end

local function monotoneChain(model, points)
    local vis = Visualization:new(model, "monotoneChain_")
    local lowerHull, upperHull = {}, {}
    -- Sort points lexicographically (x and then y)
    table.sort(points, function(a, b) return a.x == b.x and a.y < b.y or a.x < b.x end)
    -- Lower hull
    for i = 1, #points do
        while #lowerHull >= 2 and orientation(lowerHull[#lowerHull - 1], lowerHull[#lowerHull], points[i]) <= 0 do
            local rem = table.remove(lowerHull) -- pop
            vis:newView()
               :addMarks({rem}, STYLE.remMark)
               :addPolygon({lowerHull[#lowerHull], rem}, STYLE.remSegment)
               :addMarks(lowerHull, STYLE.hullMark)
               :addPolygon(lowerHull, STYLE.subHullSegment)
        end
        lowerHull[#lowerHull + 1] = points[i]
        vis:newView()
           :addMarks(lowerHull, STYLE.hullMark)
           :addPolygon(lowerHull, STYLE.subHullSegment)
    end
    -- Upper hull
    for i = #points, 1, -1 do
        while #upperHull >= 2 and orientation(upperHull[#upperHull - 1], upperHull[#upperHull], points[i]) <= 0 do
            local rem = table.remove(upperHull) -- pop
            vis:newView()
               :addMarks({rem}, STYLE.remMark)
               :addPolygon({upperHull[#upperHull], rem}, STYLE.remSegment)
               :addMarks(lowerHull, STYLE.hullMark)
               :addPolygon(lowerHull, STYLE.hullSegment)
               :addMarks(upperHull, STYLE.hullMark)
               :addPolygon(upperHull, STYLE.subHullSegment)
        end
        upperHull[#upperHull + 1] = points[i]
        vis:newView()
           :addMarks(lowerHull, STYLE.hullMark)
           :addPolygon(lowerHull, STYLE.hullSegment)
           :addMarks(upperHull, STYLE.hullMark)
           :addPolygon(upperHull, STYLE.subHullSegment)
    end
    -- Concatenate lower hull and upper hull leaving out duplicate points
    local res = lowerHull
    table.remove(res) -- pop
    for i = 1, #upperHull - 1 do
        res[#res + 1] = upperHull[i]
    end
    vis:newView("monotoneChain_result")
       :addMarks(res, STYLE.hullMark)
       :addPolygon(res, STYLE.hullSegment, true)
    return res, vis
end

local function kirkpatrickSeidel(model, points)
    local vis = Visualization:new(model, "kirkpatrickSeidel_")
    local visSubHulls = {}
    local function mergeHull(L, R)
        if #L == 0 then return R elseif #R == 0 then return L end
        local ilRight, irLeft = 1, 1
        -- Get rightmost point of left set
        for i = 1, #L do
            if L[i].x == L[ilRight].x and L[i].y > L[ilRight].y or L[i].x > L[ilRight].x then ilRight = i end
        end
        -- Get leftmost point of right set
        for i = 1, #R do
            if R[i].x == R[irLeft].x and R[i].y < R[irLeft].y or R[i].x < R[irLeft].x then irLeft = i end
        end
        -- Find upper tangent
        local il, ir = ilRight, irLeft
        local done = false
        while not done do
            done = true
            while orientation(R[ir], L[il], L[(il + 1 - 1) % #L + 1]) < 0 do
                il = (il + 1 - 1) % #L + 1
            end
            while orientation(L[il], R[ir], R[(#R + ir - 1 - 1) % #R + 1]) > 0 do
                ir = (ir - 1 - 1) % #R + 1
                done = false
            end
        end
        local iUpperTangentLeft, iUpperTangentRight = il, ir
        -- Find lower tangent
        il, ir = ilRight, irLeft
        done = false
        while not done do
            done = true
            while orientation(L[il], R[ir], R[(ir + 1 - 1) % #R + 1]) < 0 do
                ir = (ir + 1 - 1) % #R + 1
            end
            while orientation(R[ir], L[il], L[(#L + il - 1 - 1) % #L + 1]) > 0 do
                il = (il - 1 - 1) % #L + 1
                done = false
            end
        end
        local iLowerTangentLeft, iLowerTangentRight = il, ir
        -- Special case: all points are colinear -> just return sorted union
        if iUpperTangentLeft == iLowerTangentLeft and iUpperTangentRight == iLowerTangentRight then
            local hull = L
            for i = 1, #R do hull[#hull+1] = R[i] end
            table.sort(hull, function(a, b) return a.x == b.x and a.y < b.y or a.x < b.x end) -- Probably, there is a smarter way with less than O(nlog(n))...
            return hull
        end
        vis:cloneView()
           :addPolygon({L[iUpperTangentLeft], R[iUpperTangentRight]}, STYLE.checkingSegment)
           :addPolygon({L[iLowerTangentLeft], R[iLowerTangentRight]}, STYLE.checkingSegment)
        -- Merge points from upper tangent and a
        local hull = {}
        local i = iUpperTangentLeft
        hull[#hull+1] = L[i]
        while i ~= iLowerTangentLeft do
            i = (i + 1 - 1) % #L + 1
            hull[#hull+1] = L[i]
        end
        -- Merge points from lower tangent and b
        i = iLowerTangentRight
        hull[#hull+1] = R[iLowerTangentRight]
        while i ~= iUpperTangentRight do
            i = (i + 1 - 1) % #R + 1
            hull[#hull+1] = R[i]
        end
        return hull
    end
    local function getHull(subpoints)
        -- Base cases
        if #subpoints < 3 then
            visSubHulls[#visSubHulls+1] = subpoints
            return subpoints
        end
        if #subpoints < 4 then
            -- Return 3 points in ccw order
            local hull = orientation(subpoints[1], subpoints[2], subpoints[3]) > 0  and subpoints or {subpoints[1], subpoints[3], subpoints[2]}
            visSubHulls[#visSubHulls+1] = hull
            return hull
        end
        -- Partition into left and right set
        local l, r = {}, {}
        for i, p in ipairs(subpoints) do
            if i <= #subpoints//2 then l[#l+1] = p else r[#r+1] = p end
        end
        local view = vis:newView()
        for _, h in ipairs(visSubHulls) do view:addPolygon(h, STYLE.subHullSegment, true) end
        view:addMarks(l, STYLE.group1Mark)
        view:addMarks(r, STYLE.group2Mark)
        -- Merge left and right sub-hull
        local leftHull, rightHull = getHull(l), getHull(r)
        view = vis:newView()
        for _, h in ipairs(visSubHulls) do view:addPolygon(h, STYLE.subHullSegment, true) end
        local hull = mergeHull(leftHull, rightHull)
        table.remove(visSubHulls) -- pop
        table.remove(visSubHulls) -- pop
        visSubHulls[#visSubHulls+1] = hull

        return hull
    end

    table.sort(points, function(a, b) return a.x == b.x and a.y < b.y or a.x < b.x end)
    local hull = getHull(points)
    vis:newView("kirkpatrickSeidel_result")
       :addMarks(hull, STYLE.hullMark)
       :addPolygon(hull, STYLE.hullSegment, true)
    return hull, vis
end

local function chansAlgorithm(model, points)
    local vis = Visualization:new(model)
    local function grahamScan(points) -- same implementation as above, but without visualization
        local P = getLowerLeftPoint(points)
        table.sort(points, function(a, b)
            local dirA, dirB = a - P, b - P
            local angA, angB = dirA:angle(), dirB:angle()
            local lenA, lenB = dirA:sqLen(), dirB:sqLen()
            return angA == angB and lenA < lenB or angA < angB
        end)
        local hull_stack = {}
        for i = 1, #points do
            while #hull_stack >= 2 and orientation(hull_stack[#hull_stack - 1], hull_stack[#hull_stack], points[i]) <= 0 do
                table.remove(hull_stack)
            end
            hull_stack[#hull_stack + 1] = points[i]
        end
        return hull_stack
    end
    local function findTangent(hull, p) -- find rightmost point as seen from p
        -- TODO: implement as binary search with O(log(n))
        for i = 1, #hull do
            local iPrev, iNext = (i-2) % #hull + 1, i % #hull + 1
            if orientation(p, hull[iPrev], hull[i]) <= 0 and orientation(p, hull[i], hull[iNext]) > 0 then
                return i
            end
        end
        _G.error("unreachable")
    end
    local function lowestLeftSubhullPoint(hulls)
        local h, p = 1, 1
        for i = 1, #hulls do
            local minIndex, minY, minX = 1, hulls[i][1].y, hulls[i][1].y
            for j = 1, #hulls[i] do
                if hulls[i][j].y < minY or (hulls[i][j].y == minY and hulls[i][j].x < minX) then
                    minIndex, minY, minX = j, hulls[i][j].y, hulls[i][j].x
                end
            end
            if hulls[i][minIndex].y < hulls[h][p].y or (hulls[i][minIndex].y == hulls[h][p].y and hulls[i][minIndex].x < hulls[h][p].x) then
                h, p = i, minIndex
            end
        end
        return { iHull = h, iPoint = p }
    end
    local function nextSubhullPoint(hulls, prev)
        local p = hulls[prev.iHull][prev.iPoint]
        local next = { iHull = prev.iHull, iPoint = prev.iPoint % #hulls[prev.iHull] + 1 }
        for h = 1, #hulls do
            if h ~= prev.iHull then
                local iTangent = findTangent(hulls[h], p)
                local q, r = hulls[next.iHull][next.iPoint], hulls[h][iTangent]
                local t = orientation(p, q, r)
                if t < 0 or t == 0 and (r - p):sqLen() > (q - p):sqLen() then
                    next = { iHull = h, iPoint = iTangent }
                end
            end
        end
        return next
    end

    local m = 4
    while true do
        vis.namePrefix = "chan_m" .. m .. "_"
        local groups = partitionByGroupSize(points, m)
        -- Compute each subset's CH with graham scan
        local subHulls = {}
        for _, group in ipairs(groups) do
            subHulls[#subHulls + 1] = grahamScan(group)
        end

        vis:newView()
        for i, h in ipairs(subHulls) do -- draw all sub-hulls in different colors
            attrs = cloneTable(STYLE.subHullSegment)
            attrs.stroke = COLOR_PALETTE[(i-1) % #COLOR_PALETTE + 1]
            vis:cloneView()
               :addPolygon(h, attrs, true)
        end
        local subHullsView = vis.views[#vis.views]

        -- Perform gift wrapping starting from lowest point, which is guaranteed to be on overall CH
        local hull = { lowestLeftSubhullPoint(subHulls) }
        local res = { subHulls[hull[1].iHull][hull[1].iPoint] }
        for _ = 1, m do
            local p = nextSubhullPoint(subHulls, hull[#hull])
            if p.iHull == hull[1].iHull and p.iPoint == hull[1].iPoint then
                vis:newView("chan_result")
                   :addMarks(res, STYLE.hullMark)
                   :addPolygon(res, STYLE.hullSegment, true)
                return res, vis
            end
            hull[#hull + 1] = p
            res[#res+1] = subHulls[p.iHull][p.iPoint]

            vis:cloneView(subHullsView)
               :addPolygon(res, STYLE.subHullSegment, false)
               :addMarks(res, STYLE.hullMark)
        end
        vis:cloneView(subHullsView)
           :addPolygon(res, STYLE.remSegment, false)
        m = m * m
    end
end

------------------------------------------------------
local algorithms = {
    bruteForce,
    grahamScan,
    jarvisMarch,
    quickHull,
    monotoneChain,
    kirkpatrickSeidel,
    chansAlgorithm
}

function run(model, algoNum)
    -- if true then
    --     print(dump(model.attributes))
    --     return
    -- end
    if algoNum > #algorithms then model:warning("Unknown algorithm: " .. algoNum) return end

    local points = collectPoints(model)
    if points == nil then return end
    points = removeDuplicatePoints(points)
    shuffleTable(points) -- Randomize order of points for more interesting visualizations

    local hull_points, views = algorithms[algoNum](model, points) -- Run specified algorithm
    views:generateIpeViews()

    print(dump(hull_points))
end

methods = {
    { label = "Draw convex hull with Brute-Force" },
    { label = "Draw convex hull with Graham Scan" },
    { label = "Draw convex hull with Jarvis-March" },
    { label = "Draw convex hull with Quickhull" },
    { label = "Draw convex hull with Andrew's Monotone Chain" },
    { label = "Draw convex hull with Kirkpatrick-Seidel algorithm" },
    { label = "Draw convex hull with Chans algorithm" }
}