package rosegold.outlines;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.Map;
import java.util.TreeMap;
import java.util.TreeSet;

public class Extract {
    private static final String BLOCK = "net.minecraft.world.level.block.Block";
    private static final String STATE = "net.minecraft.world.level.block.state.BlockState";
    private static final String BEHAVIOUR = "net.minecraft.world.level.block.state.BlockBehaviour";
    private static final String STATE_BASE = BEHAVIOUR + "$BlockStateBase";
    private static final String STATE_HOLDER = "net.minecraft.world.level.block.state.StateHolder";
    private static final String PROPERTY = "net.minecraft.world.level.block.state.properties.Property";
    private static final String BLOCK_GETTER = "net.minecraft.world.level.BlockGetter";
    private static final String POS = "net.minecraft.core.BlockPos";
    private static final String CONTEXT = "net.minecraft.world.phys.shapes.CollisionContext";
    private static final String SHAPE = "net.minecraft.world.phys.shapes.VoxelShape";
    private static final String AABB = "net.minecraft.world.phys.AABB";
    private static final String VEC = "net.minecraft.world.phys.Vec3";
    private static final String REGISTRY = "net.minecraft.core.Registry";
    private static final String REGISTRIES = "net.minecraft.core.registries.BuiltInRegistries";
    private static final String EMPTY_GETTER = "net.minecraft.world.level.EmptyBlockGetter";

    private final Map<String, String> names = new HashMap<>();
    private final boolean mapped;

    private Extract(String mappings) throws Exception {
        mapped = !mappings.equals("-");
        if (!mapped) return;
        try (BufferedReader lines = Files.newBufferedReader(Path.of(mappings))) {
            String owner = null;
            for (String line; (line = lines.readLine()) != null;) {
                int arrow = line.lastIndexOf(" -> ");
                if (arrow < 0 || line.startsWith("#")) continue;
                String key = line.substring(0, arrow);
                String name = line.substring(arrow + 4);
                if (line.startsWith(" ")) {
                    key = key.strip();
                    names.put(owner + " " + key.substring(key.indexOf(' ') + 1), name);
                } else {
                    owner = key;
                    names.put(owner, name.substring(0, name.length() - 1));
                }
            }
        }
    }

    private String mappedName(String owner, String signature) {
        if (mapped) {
            String key = signature == null ? owner : owner + " " + signature;
            String name = names.get(key);
            if (name == null) throw new IllegalArgumentException("Missing mapping for " + key);
            return name;
        }
        if (signature == null) return owner;
        int params = signature.indexOf('(');
        return params < 0 ? signature : signature.substring(0, params);
    }

    private Class<?> type(String name) throws Exception {
        return Class.forName(name.startsWith("java.") ? name : mappedName(name, null), false, Extract.class.getClassLoader());
    }

    private Method method(String owner, String name, String... params) throws Exception {
        Class<?>[] types = new Class<?>[params.length];
        for (int i = 0; i < params.length; i++) types[i] = type(params[i]);
        return type(owner).getMethod(mappedName(owner, name + "(" + String.join(",", params) + ")"), types);
    }

    private Object staticField(String owner, String name) throws Exception {
        return type(owner).getField(mappedName(owner, name)).get(null);
    }

    private List<double[]> boxes(Method toAabbs, Object shape) throws Exception {
        List<double[]> boxes = new ArrayList<>();
        for (Object box : (List<?>) toAabbs.invoke(shape)) {
            double[] coords = new double[6];
            for (int i = 0; i < coords.length; i++) coords[i] = aabbFields[i].getDouble(box);
            boxes.add(coords);
        }
        boxes.sort(Arrays::compare);
        return boxes;
    }

    private java.lang.reflect.Field[] aabbFields;

    private static Object traced(Class<?> type, Object delegate, Map<String, String> namedMethods, TreeSet<String> calls,
                                 Set<Object> queriedItems, Object heldItem) {
        return Proxy.newProxyInstance(Extract.class.getClassLoader(), new Class<?>[]{type}, (proxy, method, args) -> {
            String name = namedMethods.getOrDefault(method.getName() + "/" + method.getParameterCount(), method.getName());
            calls.add(name);
            if (name.equals("isHoldingItem")) {
                queriedItems.add(args[0]);
                return args[0] == heldItem;
            }
            try {
                return method.invoke(delegate, args);
            } catch (InvocationTargetException e) {
                throw e.getCause();
            }
        });
    }

    private static boolean equalBoxes(List<double[]> left, List<double[]> right) {
        return Arrays.deepEquals(left.toArray(), right.toArray());
    }

    private static List<double[]> translate(List<double[]> boxes, double[] offset, int direction) {
        var shifted = new ArrayList<double[]>(boxes.size());
        for (double[] box : boxes) {
            double[] copy = box.clone();
            for (int i = 0; i < copy.length; i++) copy[i] += direction * offset[i % 3];
            shifted.add(copy);
        }
        return shifted;
    }

    private static boolean sameTranslation(List<double[]> left, List<double[]> right) {
        if (left.size() != right.size()) return false;
        for (int box = 0; box < left.size(); box++) {
            for (int i = 0; i < 6; i++) {
                if (Math.abs(left.get(box)[i] - right.get(box)[i]) > 1e-9) return false;
            }
        }
        return true;
    }

    private static void writeBoxes(BufferedWriter writer, List<double[]> boxes) throws Exception {
        for (double[] box : boxes) {
            for (double coord : box) writer.write(Double.toString(coord) + ",");
        }
    }

    private void extract(Path output, Path audit) throws Exception {
        method("net.minecraft.SharedConstants", "tryDetectVersion").invoke(null);
        method("net.minecraft.server.Bootstrap", "bootStrap").invoke(null);
        Object blockRegistry = staticField(REGISTRIES, "BLOCK");
        Object itemRegistry = staticField(REGISTRIES, "ITEM");
        Iterable<?> states = (Iterable<?>) staticField(BLOCK, "BLOCK_STATE_REGISTRY");
        Method blockId = method(REGISTRY, "getId", "java.lang.Object");
        Method stateId = method(BLOCK, "getId", STATE);
        Method blockKey = method(REGISTRY, "getKey", "java.lang.Object");
        Method stateBlock = method(STATE_BASE, "getBlock");
        Method outline = method(STATE_BASE, "getShape", BLOCK_GETTER, POS, CONTEXT);
        Method interaction = method(STATE_BASE, "getInteractionShape", BLOCK_GETTER, POS);
        Method hasOffset = method(STATE_BASE, "hasOffsetFunction");
        Method offset = method(STATE_BASE, "getOffset", POS);
        Method toAabbs = method(SHAPE, "toAabbs");
        Method getValues = method(STATE_HOLDER, "getValues");
        Method getName = method(PROPERTY, "getName");
        Method valueName = mapped ? method(PROPERTY, "getName", "java.lang.Comparable") : method(PROPERTY + "$Value", "valueName");
        Method valueProperty = mapped ? null : method(PROPERTY + "$Value", "property");
        Object getter = staticField(EMPTY_GETTER, "INSTANCE");
        Object context = method(CONTEXT, "empty").invoke(null);
        var position = type(POS).getConstructor(int.class, int.class, int.class);
        Object origin = position.newInstance(0, 0, 0);
        List<Object> elsewhere = List.of(position.newInstance(91, 17, -31), position.newInstance(-22, 65, 100),
                                         position.newInstance(7, 0, 12));
        String[] axes = {"x", "y", "z"};
        var offsetFields = new java.lang.reflect.Field[axes.length];
        for (int i = 0; i < axes.length; i++) offsetFields[i] = type(VEC).getField(mappedName(VEC, axes[i]));
        Method maxHorizontal = type(BEHAVIOUR).getDeclaredMethod(mappedName(BEHAVIOUR, "getMaxHorizontalOffset()"));
        Method maxVertical = type(BEHAVIOUR).getDeclaredMethod(mappedName(BEHAVIOUR, "getMaxVerticalOffset()"));
        maxHorizontal.setAccessible(true);
        maxVertical.setAccessible(true);
        String[] coordNames = {"minX", "minY", "minZ", "maxX", "maxY", "maxZ"};
        aabbFields = new java.lang.reflect.Field[coordNames.length];
        for (int i = 0; i < coordNames.length; i++) aabbFields[i] = type(AABB).getField(mappedName(AABB, coordNames[i]));

        TreeSet<String> getterCalls = new TreeSet<>();
        TreeSet<String> contextCalls = new TreeSet<>();
        Map<String, String> getters = new HashMap<>();
        for (String name : List.of("getBlockState", "getBlockEntity", "getFluidState")) {
            getters.put(mappedName(BLOCK_GETTER, name + "(" + POS + ")") + "/1", name);
        }
        Map<String, String> contexts = new HashMap<>();
        for (String[] entry : new String[][]{{"isHoldingItem", "net.minecraft.world.item.Item"}, {"isDescending"},
                {"isAbove", SHAPE, POS, "boolean"}}) {
            contexts.put(mappedName(CONTEXT, entry[0] + "(" + String.join(",", Arrays.copyOfRange(entry, 1, entry.length)) + ")")
                    + "/" + (entry.length - 1), entry[0]);
        }
        Set<Object> queriedItems = new HashSet<>();
        Object tracedGetter = traced(type(BLOCK_GETTER), getter, getters, getterCalls, Set.of(), null);
        Object tracedContext = traced(type(CONTEXT), context, contexts, contextCalls, queriedItems, null);
        Map<String, TreeSet<String>> diagnostics = new TreeMap<>();

        try (BufferedWriter writer = Files.newBufferedWriter(output)) {
            for (Object state : states) {
                Object block = stateBlock.invoke(state);
                String name = blockKey.invoke(blockRegistry, block).toString();
                int bid = (int) blockId.invoke(blockRegistry, block);
                int sid = (int) stateId.invoke(null, state);
                try {
                    List<double[]> shape = boxes(toAabbs, outline.invoke(state, getter, origin, context));
                    writer.write(bid + "\t" + sid + "\t" + name + "\t");
                    var values = new TreeMap<String, String>();
                    Object properties = getValues.invoke(state);
                    if (properties instanceof Map<?, ?> map) {
                        for (var prop : map.entrySet()) {
                            values.put((String) getName.invoke(prop.getKey()), (String) valueName.invoke(prop.getKey(), prop.getValue()));
                        }
                    } else {
                        try (var stream = (java.util.stream.Stream<?>) properties) {
                            for (Object prop : stream.toArray()) {
                                values.put((String) getName.invoke(valueProperty.invoke(prop)), (String) valueName.invoke(prop));
                            }
                        }
                    }
                    for (var prop : values.entrySet()) writer.write(prop.getKey() + "=" + prop.getValue() + ",");
                    writer.write('\t');
                    if (!boxes(toAabbs, interaction.invoke(state, getter, origin)).isEmpty()) {
                        record(diagnostics, "nonempty interaction shape", name);
                    }
                    getterCalls.clear();
                    contextCalls.clear();
                    queriedItems.clear();
                    if (!equalBoxes(shape, boxes(toAabbs, outline.invoke(state, tracedGetter, origin, tracedContext)))) {
                        throw new IllegalStateException("Concrete getter or context affects outline");
                    }
                    for (String call : getterCalls) record(diagnostics, "outline reads world: " + call, name);
                    for (String call : contextCalls) record(diagnostics, "outline reads context: " + call, name);

                    var samples = new ArrayList<List<double[]>>();
                    for (Object pos : elsewhere) samples.add(boxes(toAabbs, outline.invoke(state, getter, pos, context)));
                    boolean moves = samples.stream().anyMatch(sample -> !equalBoxes(shape, sample));
                    double[] originOffset = new double[3];
                    boolean offsets = (boolean) hasOffset.invoke(state);
                    if (offsets) {
                        Object vec = offset.invoke(state, origin);
                        for (int i = 0; i < 3; i++) originOffset[i] = offsetFields[i].getDouble(vec);
                        record(diagnostics, originOffset[1] != 0 ? "XYZ offset" : "XZ offset", name);
                    }
                    if (moves) {
                        if (!offsets) throw new IllegalStateException("Outline changes position without an offset function");
                        var neutral = translate(shape, originOffset, -1);
                        for (int pos = 0; pos < elsewhere.size(); pos++) {
                            Object vec = offset.invoke(state, elsewhere.get(pos));
                            double[] shift = new double[3];
                            for (int i = 0; i < 3; i++) shift[i] = offsetFields[i].getDouble(vec);
                            if (!sameTranslation(translate(neutral, shift, 1), samples.get(pos))) {
                                throw new IllegalStateException("Outline position changes by more than its offset");
                            }
                        }
                        record(diagnostics, "position-dependent outline", name);
                        writeBoxes(writer, neutral);
                        writer.write("\t" + maxHorizontal.invoke(block) + "," + (originOffset[1] == 0 ? 0 : maxVertical.invoke(block)));
                    } else {
                        writeBoxes(writer, shape);
                        writer.write('\t');
                    }
                    writer.write('\t');
                    if (!queriedItems.isEmpty()) {
                        if (queriedItems.size() != 1) throw new IllegalStateException("Outline queries multiple held items");
                        Object item = queriedItems.iterator().next();
                        Object holding = traced(type(CONTEXT), context, contexts, contextCalls, queriedItems, item);
                        List<double[]> held = boxes(toAabbs, outline.invoke(state, getter, origin, holding));
                        if (queriedItems.size() != 1) throw new IllegalStateException("Held outline queries multiple held items");
                        if (!equalBoxes(shape, held)) {
                            writer.write(blockKey.invoke(itemRegistry, item).toString());
                            writer.write('\t');
                            writeBoxes(writer, moves ? translate(held, originOffset, -1) : held);
                        } else {
                            writer.write('\t');
                        }
                    } else {
                        writer.write('\t');
                    }
                    writer.newLine();
                } catch (InvocationTargetException e) {
                    throw new IllegalStateException("Could not extract " + name + " state " + sid, e.getCause());
                }
            }
        }
        try (BufferedWriter writer = Files.newBufferedWriter(audit)) {
            for (var entry : diagnostics.entrySet()) {
                writer.write(entry.getKey() + " (" + entry.getValue().size() + "): " + String.join(" ", entry.getValue()));
                writer.newLine();
            }
        }
    }

    private static void record(Map<String, TreeSet<String>> diagnostics, String kind, String name) {
        diagnostics.computeIfAbsent(kind, ignored -> new TreeSet<>()).add(name);
    }

    public static void main(String[] args) throws Exception {
        new Extract(args[0]).extract(Path.of(args[1]), Path.of(args[2]));
    }
}
